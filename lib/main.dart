import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'package:path_provider/path_provider.dart';

import 'link/mac_link.dart' show DiscoveredMac, MacLink;
import 'link/models.dart';
import 'link/phone_server.dart';
import 'services/audio_capture.dart';
import 'services/brain_host.dart';
import 'llm/llm_provider.dart' show BlueyStatus;
import 'services/characters.dart';
import 'services/conversation.dart';
import 'services/perf_monitor.dart';
import 'services/permission_watchdog.dart';
import 'services/tutorial.dart';
import 'services/routines.dart';
import 'services/safety_gate.dart';
import 'services/strings.dart';
import 'services/biometric_lock.dart';
import 'services/haptics.dart';
import 'services/host_control.dart';
import 'services/onboarding_checks.dart';
import 'services/support_matrix.dart';
import 'services/request_runner.dart';
import 'services/speak_receipts.dart';
import 'services/speech.dart';
import 'services/tool_executor.dart';
import 'services/transcription.dart';
import 'ui/face_screen.dart';
import 'ui/permission_recovery_card.dart';
import 'ui/tutorial_card.dart';
import 'ui/lock_gate.dart';
import 'ui/onboarding_screen.dart';
import 'ui/theme.dart';
import 'ui/settings_screen.dart';
import 'ui/unsupported_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Strings.load();
  await RoutineStore.instance.load();
  await CharacterStore.instance.load();
  await BiometricLock.instance.load();
  await ThemeController.instance.load();
  final profile = SupportMatrix.profile();
  if (profile.supports(SupportMatrix.windowManagement)) {
    await windowManager.ensureInitialized();
  }
  runApp(LocalBlueyApp(home: homeForProfile(profile)));
}

/// Picks the home screen from the support matrix (#84): unsupported
/// platforms get an explanatory screen, never the client UI.
Widget homeForProfile(PlatformProfile profile) => switch (profile.role) {
  AppRole.host => const MacHome(),
  AppRole.phoneClient => const LockGate(
    reason: 'Unlock the Bluey remote',
    child: IosHome(),
  ),
  AppRole.unsupported => UnsupportedScreen(profile: profile),
};

class LocalBlueyApp extends StatelessWidget {
  const LocalBlueyApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => MaterialApp(
        title: 'Local Bluey',
        debugShowCheckedModeBanner: false,
        // Light + dark from one token set, following the system (#87).
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeController.instance.mode,
        builder: (context, child) => Directionality(
          textDirection: Strings.forceRtl
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        ),
        home: home,
      ),
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

class _MacHomeState extends State<MacHome>
    with TrayListener, WidgetsBindingObserver {
  bool _showOnboarding = false;
  final _watchdog = PermissionWatchdog(checker: const LivePermissionChecker());
  List<OnboardingPermission> _revoked = [];
  final _tutorial = TutorialController.instance;
  final _server = PhoneServer();
  final _face = ValueNotifier<FaceState>(FaceState(mood: Mood.resting));
  bool _awake = false;
  bool _trusted = false;
  String? _bubble;
  final _capture = AudioCapture();
  final _receipts = SpeakReceipts();
  final _transcription = TranscriptionService();
  final _speech = SpeechService();
  final _tools = ToolExecutor();
  final _safety = SafetyGate();

  BlueyStatus _status = BlueyStatus.listening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    trayManager.addListener(this);
    _setupTray();
    _server.onPairRequest = _askToPair;
    _server.start();
    _server.requests.listen(_onPhoneRequest);
    _receipts.failures.listen((line) {
      if (mounted) setState(() => _bubble = '$line (long-press to retry)');
    });
    _checkTrust();
    BrainHost.reload();
    ConversationStore.instance.load();
    OnboardingScreen.isDone().then((done) {
      if (!done && mounted) setState(() => _showOnboarding = true);
    });
    _recheckPermissions();
    TutorialController.isDone().then((done) {
      if (done) _tutorial.dismiss();
    });
    _tutorial.addListener(_onTutorialChanged);
    _tools.onPointed = _tutorial.notifyPointed;
    _tools.isCancelled = () => _safety.killed;
    _safety.frontAppProvider = () => _tools.lastFrontApp;
    _safety.onConfirm = _confirmAction;
    _safety.onKill(() {
      setState(() => _bubble = 'Stopped.');
      BrainHost.brain.value?.reset();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from System Settings re-checks for revoked grants (#174).
    if (state == AppLifecycleState.resumed) _recheckPermissions();
  }

  Future<void> _recheckPermissions() async {
    final revoked = await _watchdog.recheckRevoked();
    if (mounted) setState(() => _revoked = revoked);
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
    final trusted = await HostControl.forPlatform().isTrusted();
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
          MenuItem(key: 'ask', label: 'Ask Bluey (wake)'),
          MenuItem(key: 'mute', label: 'Mute replies'),
          MenuItem(key: 'status', label: 'Status'),
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
      case 'ask':
        // Tray quick action (#91): same wake path as the face gesture.
        setState(() => _awake = true);
        _server.broadcast(Packet(command: 'wake'));
      case 'mute':
        // Tray quick action (#91): stop any in-flight speech.
        unawaited(_speech.stop());
        _server.broadcast(Packet(command: 'stopSpeech'));
      case 'status':
        setState(
          () => _bubble = _safety.killed
              ? 'Stopped (kill switch).'
              : _awake
              ? 'Awake and listening.'
              : 'Sleeping - wake me from the tray or phone.',
        );
      case 'stop':
        _safety.kill();
      case 'resume':
        _safety.reset();
      case 'quit':
        exit(0);
    }
  }

  void _onPhoneRequest(Packet packet) {
    // Spoken-reply receipts from the phone (#87).
    if ((packet.command == 'playing' || packet.command == 'done') &&
        packet.speech != null) {
      _receipts.ack(packet.speech);
      return;
    }
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
    if (awake) _tutorial.notifyAwake();
    setState(() {
      _awake = awake;
      _face.value = FaceState(mood: awake ? Mood.listening : Mood.sleepy);
      if (awake) {
        final line = CharacterStore.instance.current.value.react(
          'wake',
          DateTime.now().millisecond,
        );
        if (line.isNotEmpty) _bubble = line;
      }
    });
    _server.sendFace(_face.value);
    _server.broadcast(Packet(command: awake ? 'wake' : 'sleep'));
  }

  Future<void> _onHoldEnd() async {
    final file = await _capture.stop();
    if (file == null) {
      setState(() {
        _bubble = null;
        _face.value = FaceState(mood: _awake ? Mood.listening : Mood.sleepy);
      });
      return;
    }
    await _processUtterance(file);
  }

  late final RequestRunner _runner = RequestRunner(
    transcriber: _transcription,
    safety: _safety,
    tools: _tools,
    speech: _speech,
    hooks: _RunnerHooks(this),
  );

  Future<void> _processUtterance(File file) async {
    _runner.awake = _awake;
    await _runner.process(file);
  }

  void _applyBubble(String? text) {
    if (mounted) setState(() => _bubble = text);
  }

  void _applyStatus(BlueyStatus status) {
    if (mounted) setState(() => _status = status);
  }

  void _applyFace(FaceState face) {
    if (mounted) setState(() => _face.value = face);
  }

  void _onTutorialChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tutorial.removeListener(_onTutorialChanged);
    WidgetsBinding.instance.removeObserver(this);
    trayManager.removeListener(this);
    _server.stop();
    _capture.dispose();
    _speech.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding) {
      return OnboardingScreen(
        onDone: () {
          _watchdog.recordGranted();
          setState(() => _showOnboarding = false);
        },
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Brain settings',
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const LockGate(
                    reason: 'Unlock Bluey settings',
                    child: SettingsScreen(),
                  ),
                ),
              );
              if (saved ?? false) BrainHost.reload();
            },
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: KeyboardListener(
        focusNode: FocusNode(skipTraversal: false, canRequestFocus: true)
          ..requestFocus(),
        autofocus: true,
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyW) {
            _setAwake(!_awake);
          }
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.space) {
            _face.value = FaceState(mood: Mood.listening);
            _capture.hasPermission().then((ok) {
              if (ok) _capture.start();
            });
            setState(() => _bubble = 'Listening…');
          }
          if (event is KeyUpEvent &&
              event.logicalKey == LogicalKeyboardKey.space) {
            _onHoldEnd();
          }
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 0),
              child: TutorialCard(controller: _tutorial),
            ),
            if (_revoked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 0),
                child: PermissionRecoveryCard(
                  permission: _revoked.first,
                  onDismiss: () {
                    _watchdog.clearBaseline(_revoked.first.id);
                    setState(() => _revoked = _revoked.sublist(1));
                  },
                ),
              ),
            Expanded(
              child: ValueListenableBuilder<FaceState>(
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
                  perfOverlay: ValueListenableBuilder<bool>(
                    valueListenable: PerfMonitor.instance.overlayEnabled,
                    builder: (context, enabled, _) {
                      if (!enabled) return const SizedBox.shrink();
                      final medians = PerfMonitor.instance.medians();
                      if (medians.isEmpty) return const SizedBox.shrink();
                      final text = medians.entries
                          .map((e) => '${e.key}: ${e.value}ms')
                          .join('  ·  ');
                      return Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: BrainHost.refusedReason,
            builder: (context, refused, _) {
              if (refused != null) {
                return MaterialBanner(
                  content: Text(refused),
                  actions: const [SizedBox.shrink()],
                );
              }
              if (BrainHost.remoteActive.value) {
                return const MaterialBanner(
                  content: Text(
                    'Cloud provider active - data leaves this Mac.',
                  ),
                  actions: [SizedBox.shrink()],
                );
              }
              return const SizedBox.shrink();
            },
          ),
          if (!_trusted)
            MaterialBanner(
              content: const Text(
                'Local Bluey needs Accessibility permission to point and click.',
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final host = HostControl.forPlatform();
                    await host.askPermission();
                    await host.openAccessibilitySettings();
                  },
                  child: const Text('Open settings'),
                ),
              ],
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
    unawaited(RemoteHaptics.instance.load());
    _link = MacLink(deviceName: SupportMatrix.deviceName());
    _link.faces.listen((face) {
      if (mounted) setState(() => _face = face);
    });
    _link.connected.listen((connected) {
      if (mounted) setState(() => _connected = connected);
      // Connect/disconnect get their own haptic (#88).
      unawaited(
        RemoteHaptics.instance.fire(
          connected ? RemoteHapticEvent.connect : RemoteHapticEvent.disconnect,
        ),
      );
    });
    _link.packets.listen((packet) async {
      if (packet.command == 'say' && packet.text != null) {
        setState(() => _bubble = packet.text);
        unawaited(RemoteHaptics.instance.fire(RemoteHapticEvent.answer));
        if (packet.audio != null) {
          final bytes = base64Decode(packet.audio!);
          final file = File(
            '${(await getTemporaryDirectory()).path}/bluey_say_'
            '${DateTime.now().millisecondsSinceEpoch}.mp3',
          );
          await file.writeAsBytes(bytes, flush: true);
          // Receipts: playback start + completion (#87).
          _link.send(Packet(command: 'playing', speech: packet.speech));
          await _player.play(DeviceFileSource(file.path));
          await _player.onPlayerComplete.first;
          _link.send(Packet(command: 'done', speech: packet.speech));
        } else {
          // Text-only reply: display is the receipt (#87).
          _link.send(Packet(command: 'done', speech: packet.speech));
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
        status: _connected ? BlueyStatus.listening : BlueyStatus.offline,
        onWakeChanged: (awake) {
          setState(() => _awake = awake);
          _link.send(Packet(command: awake ? 'wake' : 'sleep'));
        },
        onHoldStart: () async {
          setState(() => _bubble = 'Listening…');
          _link.send(Packet(command: 'holdStart'));
          unawaited(RemoteHaptics.instance.fire(RemoteHapticEvent.holdStart));
          if (await _capture.hasPermission()) {
            await _capture.start();
          } else {
            unawaited(RemoteHaptics.instance.fire(RemoteHapticEvent.error));
          }
        },
        onHoldEnd: () async {
          setState(() => _bubble = null);
          _link.send(Packet(command: 'holdEnd'));
          final file = await _capture.stop();
          if (file != null) {
            try {
              final bytes = await file.readAsBytes();
              _link.send(
                Packet(command: 'holdAudio', audio: base64Encode(bytes)),
              );
            } finally {
              await AudioCapture.deleteQuietly(file); // #116
            }
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
                TextButton(
                  onPressed: _pickMac,
                  child: const Text('Choose Mac'),
                ),
              ],
            ),
    );
  }
}

class _RunnerHooks extends RequestHooks {
  _RunnerHooks(this._home);

  final _MacHomeState _home;

  @override
  void bubble(String? text) {
    if (text != null) _home._tutorial.notifyAnswer();
    _home._applyBubble(text);
  }

  @override
  void status(BlueyStatus status) {
    _home._applyStatus(status);
  }

  @override
  void face(FaceState face) {
    _home._applyFace(face);
  }

  @override
  void sendFace(FaceState face) => _home._server.sendFace(face);

  @override
  void say(Packet packet, String spoken) {
    _home._receipts.track(packet, spoken); // receipt required (#87)
    _home._server.broadcast(packet);
  }
}
