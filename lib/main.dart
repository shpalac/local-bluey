import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'link/mac_link.dart';
import 'link/models.dart';
import 'link/phone_server.dart';
import 'services/brain_host.dart';
import 'services/native_control.dart';
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

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    _setupTray();
    _server.start();
    _server.requests.listen(_onPhoneRequest);
    _checkTrust();
    BrainHost.reload();
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
      case 'quit':
        exit(0);
    }
  }

  void _onPhoneRequest(Packet packet) {
    if (packet.command == 'wake' || packet.command == 'sleep') {
      setState(() => _awake = packet.command == 'wake');
    }
  }

  void _setAwake(bool awake) {
    setState(() {
      _awake = awake;
      _face.value = FaceState(mood: awake ? Mood.listening : Mood.sleepy);
    });
    _server.sendFace(_face.value);
    _server.broadcast(Packet(command: awake ? 'wake' : 'sleep'));
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    _server.stop();
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
          onWakeChanged: _setAwake,
          onHoldStart: () {
            setState(() {
              _face.value = FaceState(mood: Mood.listening);
              _bubble = 'Listening…';
            });
          },
          onHoldEnd: () {
            setState(() {
              _bubble = null;
              _face.value = FaceState(
                mood: _awake ? Mood.listening : Mood.sleepy,
              );
            });
          },
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
    _link.start();
  }

  @override
  void dispose() {
    _link.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FaceScreen(
        face: _face,
        awake: _awake,
        bubble: _bubble,
        onWakeChanged: (awake) {
          setState(() => _awake = awake);
          _link.send(Packet(command: awake ? 'wake' : 'sleep'));
        },
        onHoldStart: () {
          setState(() => _bubble = 'Listening…');
          _link.send(Packet(command: 'holdStart'));
        },
        onHoldEnd: () {
          setState(() => _bubble = null);
          _link.send(Packet(command: 'holdEnd'));
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
              actions: const [SizedBox.shrink()],
            ),
    );
  }
}
