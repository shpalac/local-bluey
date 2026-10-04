import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'package:path_provider/path_provider.dart';

import 'link/mac_link.dart' show DiscoveredMac, MacLink;
import 'link/models.dart';
import 'link/phone_server.dart';
import 'services/audio_capture.dart';
import 'services/brain_host.dart';
import 'services/native_control.dart';
import 'llm/llm_provider.dart' show BlueyStatus;
import 'services/conversation.dart';
import 'services/safety_gate.dart';
import 'services/settings_store.dart';
import 'services/speech.dart';
import 'services/tool_executor.dart';
import 'services/transcription.dart';
import 'ui/face_screen.dart';
import 'ui/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    runApp(const LocalBlueyApp(home: MacHome()));
  } else {
    runApp(const LocalBlueyApp(home: IosHome()));
  }
}

class LocalBlueyApp extends StatelessWidget {
  const LocalBlueyApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Bluey',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: home,
    );
  }
}

/// macOS: runs the face window, the menu-bar tray, and the PhoneServer that
/// iPhones discover over Bonjour.
class MacHome extends StatefulWidget {
  const MacHome({super.key});

  @override
  State<MacHome> createState() => _MacHomeState();
}

class _MacHomeState extends State<MacHome> with TrayListener {
  final _server = PhoneServer();
  final _face = ValueNotifier<FaceState>(FaceState(mood: Mood.resting));
  bool _awake = false;
  bool _trusted = false;
  String? _bubble;
  final _capture = AudioCapture();
  final _transcription = TranscriptionService();
  final _speech = SpeechService();
  final _tools = ToolExecutor();
  final _safety = SafetyGate();
  BlueyStatus _status = BlueyStatus.listening;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    _setupTray();
    _server.onPairRequest = _askToPair;
    _server.start();
    _server.requests.listen(_onPhoneRequest);
    _checkTrust();
    BrainHost.reload();
    ConversationStore.instance.load();
    _safety.onConfirm = _confirmAction;
    _safety.onKill(() {
      setState(() => _bubble = 'Stopped.');
      BrainHost.brain.value?.reset();
    });
  }

  Future<bool> _askToPair(String deviceName) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pair device?'),
        content: Text('"$deviceName" wants to connect to this Mac.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Deny'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pair'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  Future<bool> _confirmAction(String description) async {
    if (!mounted) return false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluey wants to act'),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  Future<void> _checkTrust() async {
    final trusted = await NativeControl.isTrusted();
    if (mounted) setState(() => _trusted = trusted);
  }

  Future<void> _setupTray() async {
    await trayManager.setIcon('assets/tray_icon.png');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show Bluey'),
          MenuItem(key: 'hide', label: 'Hide'),
          MenuItem.separator(),
          MenuItem(key: 'stop', label: 'Stop Bluey (kill switch)'),
          MenuItem(key: 'resume', label: 'Resume Bluey'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
      case 'hide':
        windowManager.hide();
      case 'stop':
        _safety.kill();
      case 'resume':
        _safety.reset();
      case 'quit':
        exit(0);
    }
  }

  void _onPhoneRequest(Packet packet) {
    if (packet.command == 'wake' || packet.command == 'sleep') {
      setState(() => _awake = packet.command == 'wake');
    }
    if (packet.command == 'holdAudio' && packet.audio != null) {
      _onPhoneAudio(base64Decode(packet.audio!));
    }
  }

  /// Phone-side hold-to-talk audio rides the link; same pipeline as the
  /// Mac's own mic.
  Future<void> _onPhoneAudio(List<int> bytes) async {
    final file = File(
      '${(await getTemporaryDirectory()).path}/bluey_phone_'
      '${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await file.writeAsBytes(bytes, flush: true);
    setState(() => _face.value = FaceState(mood: Mood.thinking));
    await _processUtterance(file);
  }

  void _setAwake(bool awake) {
    setState(() {
      _awake = awake;
      _face.value = FaceState(mood: awake ? Mood.listening : Mood.sleepy);
    });
    _server.sendFace(_face.value);
    _server.broadcast(Packet(command: awake ? 'wake' : 'sleep'));
  }

  Future<void> _onHoldEnd() async {
    final file = await _capture.stop();
    if (file == null) {
      setState(() {
        _bubble = null;
        _face.value = FaceState(
          mood: _awake ? Mood.listening : Mood.sleepy,
        );
      });
      return;
    }
    await _processUtterance(file);
  }

  /// Transcribe -> ask the brain -> run tools -> speak, with status + log.
  Future<void> _processUtterance(File file) async {
    setState(() {
      _face.value = FaceState(mood: Mood.thinking);
      _status = BlueyStatus.thinking;
    });
    try {
      final text = await _transcription.transcribe(
        file,
        await SettingsStore.load(),
      );
      if (text.isEmpty) {
        setState(() => _bubble = "Didn't catch that.");
        return;
      }
      setState(() => _bubble = text);
      ConversationStore.instance.add('user', text);
      final brain = BrainHost.brain.value;
      if (brain == null) {
        setState(() => _bubble = 'Set up the brain in settings first.');
        return;
      }
      const maxToolSteps = 5;
      const stepTimeout = Duration(seconds: 60);
      var reply = await brain
          .askStreaming(
            text,
            onToken: (partial) {
              if (mounted) setState(() => _bubble = partial);
            },
          )
          .timeout(stepTimeout);
      // Tool loop: let the brain act, then react to what happened.
      var steps = 0;
      while (reply.toolCall != null && steps < maxToolSteps) {
        if (_safety.killed) {
          setState(() => _bubble = 'Stopped.');
          return;
        }
        steps++;
        final call = reply.toolCall!;
        if (!await _safety.authorize(call.name, call.arguments)) {
          reply = await brain
              .toolResult(call.name, 'Denied by the user.')
              .timeout(stepTimeout);
          continue;
        }
        setState(() => _status = BlueyStatus.acting);
        final result = await _tools.execute(call);
        reply = await brain
            .toolResult(
              call.name,
              result.text,
              images: [
                if (result.imageBase64 != null) result.imageBase64!,
              ],
            )
            .timeout(stepTimeout);
      }
      if (reply.toolCall != null) {
        setState(() => _bubble = 'Too many steps - stopping here.');
      }
      if (reply.spoken.isNotEmpty) {
        ConversationStore.instance.add('bluey', reply.spoken);
        setState(() {
          _bubble = reply.spoken;
          _face.value = FaceState(mood: Mood.talking);
          _server.sendFace(_face.value);
        });
        final settings = await SettingsStore.load();
        try {
          final audio = await _speech.synthesize(reply.spoken, settings);
          _server.broadcast(
            Packet(command: 'say', text: reply.spoken, audio: base64Encode(audio)),
          );
          unawaited(_speech.speak(reply.spoken, settings));
        } on SpeechException catch (e) {
          _server.broadcast(Packet(command: 'say', text: reply.spoken));
          setState(() => _bubble = '${reply.spoken}\n(TTS failed: $e)');
        }
      }
    } on TranscriptionException catch (e) {
      setState(() {
        _bubble = 'Transcription failed: $e';
        _status = BlueyStatus.error;
      });
    } catch (e) {
      setState(() {
        _bubble = 'Error: $e';
        _status = BlueyStatus.error;
      });
    } finally {
      setState(() {
        _face.value = FaceState(
          mood: _awake ? Mood.listening : Mood.sleepy,
        );
        _status = BlueyStatus.listening;
        _server.sendFace(_face.value);
      });
    }
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    _server.stop();
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Brain settings',
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (saved ?? false) BrainHost.reload();
            },
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: ValueListenableBuilder<FaceState>(
        valueListenable: _face,
        builder: (context, face, _) => FaceScreen(
          face: face,
          awake: _awake,
          bubble: _bubble,
          status: _status,
          onWakeChanged: _setAwake,
          onHoldStart: () async {
            setState(() {
              _face.value = FaceState(mood: Mood.listening);
              _bubble = 'Listening…';
            });
            if (await _capture.hasPermission()) {
              await _capture.start();
            } else {
              setState(() => _bubble = 'No microphone permission.');
            }
          },
          onHoldEnd: _onHoldEnd,
        ),
      ),
      bottomNavigationBar: _trusted
          ? null
          : MaterialBanner(
              content: const Text(
                'Local Bluey needs Accessibility permission to point and click.',
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await NativeControl.askPermission();
                    await NativeControl.openAccessibilitySettings();
                  },
                  child: const Text('Open settings'),
                ),
              ],
            ),
    );
  }
}

/// iOS: finds the Mac over Bonjour and mirrors his face; hold-to-talk and
/// double-tap wake are sent to the Mac as packets.
class IosHome extends StatefulWidget {
  const IosHome({super.key});

  @override
  State<IosHome> createState() => _IosHomeState();
}

class _IosHomeState extends State<IosHome> {
  late final MacLink _link;
  final _capture = AudioCapture();
  final _player = AudioPlayer();
  FaceState _face = FaceState(mood: Mood.sleepy);
  bool _connected = false;
  bool _awake = false;
  String? _bubble;

  @override
  void initState() {
    super.initState();
    _link = MacLink(deviceName: Platform.isIOS ? 'iPhone' : 'Device');
    _link.faces.listen((face) {
      if (mounted) setState(() => _face = face);
    });
    _link.connected.listen((connected) {
      if (mounted) setState(() => _connected = connected);
    });
    _link.packets.listen((packet) async {
      if (packet.command == 'say' && packet.text != null) {
        setState(() => _bubble = packet.text);
        if (packet.audio != null) {
          final bytes = base64Decode(packet.audio!);
          final file = File(
            '${(await getTemporaryDirectory()).path}/bluey_say_'
            '${DateTime.now().millisecondsSinceEpoch}.mp3',
          );
          await file.writeAsBytes(bytes, flush: true);
          await _player.play(DeviceFileSource(file.path));
        }
      }
    });
    _link.start();
  }

  @override
  void dispose() {
    _link.stop();
    _capture.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickMac() async {
    final macs = await _link.macs.firstWhere((list) => list.isNotEmpty);
    if (!mounted) return;
    final picked = await showModalBottomSheet<DiscoveredMac>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mac in macs)
              ListTile(
                leading: const Icon(Icons.computer),
                title: Text(mac.name),
                onTap: () => Navigator.pop(context, mac),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _link.select(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FaceScreen(
        face: _face,
        awake: _awake,
        bubble: _bubble,
        status:
            _connected ? BlueyStatus.listening : BlueyStatus.offline,
        onWakeChanged: (awake) {
          setState(() => _awake = awake);
          _link.send(Packet(command: awake ? 'wake' : 'sleep'));
        },
        onHoldStart: () async {
          setState(() => _bubble = 'Listening…');
          _link.send(Packet(command: 'holdStart'));
          if (await _capture.hasPermission()) await _capture.start();
        },
        onHoldEnd: () async {
          setState(() => _bubble = null);
          _link.send(Packet(command: 'holdEnd'));
          final file = await _capture.stop();
          if (file != null) {
            final bytes = await file.readAsBytes();
            _link.send(
              Packet(command: 'holdAudio', audio: base64Encode(bytes)),
            );
          }
        },
      ),
      bottomNavigationBar: _connected
          ? null
          : MaterialBanner(
              content: Text(
                _link.macName == null
                    ? 'Looking for your Mac on the local network…'
                    : 'Connecting to ${_link.macName}…',
              ),
              actions: [
                TextButton(onPressed: _pickMac, child: const Text('Choose Mac')),
              ],
            ),
    );
  }
}
