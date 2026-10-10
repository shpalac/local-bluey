import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'link/mac_link.dart' show DiscoveredMac, MacLink;
import 'link/models.dart';
import 'link/phone_server.dart';
import 'services/audio_capture.dart';
import 'services/key_recording_intent.dart';
import 'services/brain_host.dart';
import 'services/host_reload_controller.dart';
import 'ui/host_reload_notice.dart';
import 'llm/llm_provider.dart' show BlueyStatus;
import 'services/characters.dart';
import 'services/egress_monitor.dart';
import 'services/action_log.dart';
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
import 'services/phone_audio.dart';
import 'services/phone_reply.dart';
import 'services/request_runner.dart';
import 'services/hold_key_controller.dart';
import 'services/speak_receipts.dart';
import 'services/speech.dart';
import 'services/tool_executor.dart';
import 'ui/face_screen.dart';
import 'ui/permission_recovery_card.dart';
import 'ui/tutorial_card.dart';
import 'ui/lock_gate.dart';
import 'ui/onboarding_screen.dart';
import 'ui/theme.dart';
import 'ui/settings_screen.dart';
import 'ui/unsupported_screen.dart';
import 'services/screen_watch.dart';
import 'ui/watch_banner.dart';
import 'services/watch_pipeline.dart';
import 'services/watch_driver.dart';
import 'services/watch_vision.dart';
import 'services/watch_suggestions.dart';
import 'ui/watch_suggestion_card.dart';
import 'services/frame_differ.dart';
import 'services/native_control.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Strings.load();
  await EgressMonitor.instance.load();
  await ActionLog.instance.load();
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
  AppRole.phoneClient => LockGate(
    reason: Strings.t('Unlock the Bluey remote', 'ביטול נעילת השלט של Bluey'),
    child: const IosHome(),
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
          // Always-visible watch indicator on every route (#212).
          child: WatchBanner(child: child!),
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
  final _hostReload = HostReloadController();
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
  final _speech = SpeechService();
  final _tools = ToolExecutor();
  final _safety = SafetyGate();
  late final HoldKeyController _holdKey = HoldKeyController(
    settings: HoldKeySettings.instance,
    supported: Platform.isMacOS,
    onStart: _onKeyHoldStart,
    onSend: _onKeyHoldSend,
    onCancel: _onKeyHoldCancel,
  );

  late final KeyRecordingIntent _keyRecording = KeyRecordingIntent(
    capture: _capture,
    deliver: _processUtterance,
    allowed: () => mounted && !_safety.killed,
  );

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$line (long-press to retry phone delivery)')),
        );
      }
    });
    _checkTrust();
    _keyRecording.addListener(_onKeyRecordingChanged);
    HoldKeySettings.instance.addListener(_syncHoldKey);
    HoldKeySettings.instance.load().then((_) => _syncHoldKey());
    ScreenWatch.instance.addListener(_syncWatchTray);
    ScreenWatch.instance.addListener(_syncWatchDriver);
    unawaited(_hostReload.reload());
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
      unawaited(_onKeyHoldCancel());
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

  /// Mirrors the watch session into the menu bar (#212): red countdown
  /// title while observing, plus a one-tap stop item.
  bool _trayWatchActive = false;
  WatchDriver? _watchDriver;
  final _watchSuggestions = WatchSuggestions();
  StreamSubscription<WatchSuggestion>? _watchSuggestionSub;
  WatchSuggestion? _suggestion;

  /// Starts/stops the observation pipeline with the session (#213).
  /// Existing session/local-only gates remain; watch inference uses only the
  /// selected provider, never conversation history or memory.
  void _syncWatchDriver() {
    final watch = ScreenWatch.instance;
    if (watch.isActive && _watchDriver == null) {
      final differ = FrameDiffer();
      final vision = WatchVision(
        provider: () => BrainHost.brain.value?.provider,
        snapshot: () async => (await NativeControl.snapshot()).jpeg,
        watch: watch,
      );
      final pipeline = WatchPipeline(
        // The cheap signal read enforces exclusions; heavier work below
        // runs only when the gate allows it.
        frontmost: NativeControl.watchFrontmostInfo,
        frameDiff: () async {
          // v1: full snapshot per diff tick (pixels only are compared).
          // Hardware numbers from the 213 bench run decide if a lighter
          // pixel-only capture path is needed.
          final snap = await NativeControl.snapshot();
          return differ.diff(snap.jpeg);
        },
        onVision: vision.describe,
      );
      _watchDriver = WatchDriver(pipeline: pipeline, differ: differ)..start();
      _watchSuggestions.resetSession();
      // Quiet, read-only suggestions (#214): the pipeline stream feeds the
      // policy layer; what comes out is a card the user dismisses. Screen
      // text inside it is quoted evidence, never an instruction.
      _watchSuggestionSub = _watchSuggestions.stream.listen((s) {
        if (mounted) setState(() => _suggestion = s);
      });
      pipeline.stream.listen(_watchSuggestions.onEvent);
    } else if (!watch.isActive && _watchDriver != null) {
      _watchDriver!.stop();
      _watchDriver = null;
      _watchSuggestionSub?.cancel();
      _watchSuggestionSub = null;
      _watchSuggestions.resetSession();
      if (_suggestion != null) setState(() => _suggestion = null);
    }
  }

  Future<void> _syncWatchTray() async {
    final watch = ScreenWatch.instance;
    if (watch.isActive) {
      final r = watch.remaining;
      final mm = r.inMinutes.remainder(60).toString().padLeft(2, '0');
      final ss = r.inSeconds.remainder(60).toString().padLeft(2, '0');
      await trayManager.setTitle('● $mm:$ss');
    } else {
      await trayManager.setTitle('');
    }
    // The menu only changes when the session starts or stops (the stop item
    // appears/disappears); rebuilding it on every one-second tick would
    // churn the native menu for no reason.
    if (watch.isActive != _trayWatchActive) {
      _trayWatchActive = watch.isActive;
      await _setupTray();
    }
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
          if (ScreenWatch.instance.isActive)
            MenuItem(key: 'stopwatch', label: 'Stop watching (kill switch)'),
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
      case 'stopwatch':
        ScreenWatch.instance.stop();
      case 'stop':
        _safety.kill();
        _holdKey.reset();
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
      _phoneAudio.handle(packet.audio!);
    }
  }

  /// Phone-side hold-to-talk audio rides the link; same pipeline as the
  /// Mac's own mic.
  late final _phoneAudio = PhoneAudioReceiver(
    process: (file) {
      if (mounted) setState(() => _face.value = FaceState(mood: Mood.thinking));
      return _processUtterance(file);
    },
    onRejected: _applyBubble,
    isActive: () => mounted,
  );

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

  void _syncHoldKey() => unawaited(_holdKey.sync());

  /// The global hold-to-talk key was held long enough (#228). Same flow as
  /// the face gesture; wakes first when asleep and respects the kill switch.
  Future<void> _onKeyHoldStart() async {
    if (!mounted || _safety.killed) return;
    if (!_awake) _setAwake(true);
    await _runKeyIntent(_keyRecording.start);
  }

  /// Key release has its own intent; ordinary face release is unchanged.
  Future<void> _onKeyHoldSend() => _runKeyIntent(_keyRecording.send);

  /// Esc/reset/kill invalidates key permission/start before ordered cleanup.
  Future<void> _onKeyHoldCancel() => _runKeyIntent(_keyRecording.cancel);

  Future<void> _runKeyIntent(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Owner publishes only current safe errors; stale effects stay contained.
    }
  }

  void _onKeyRecordingChanged() {
    if (!mounted || _safety.killed) return;
    setState(() {
      _bubble = switch (_keyRecording.status) {
        KeyRecordingStatus.pending ||
        KeyRecordingStatus.listening => 'Listening…',
        KeyRecordingStatus.denied => 'No microphone permission.',
        KeyRecordingStatus.empty => Strings.t(
          "I didn't catch that - hold and speak a little longer.",
          'לא הצלחתי לשמוע - החזיקו ודברו מעט יותר.',
        ),
        KeyRecordingStatus.failed =>
          'Could not finish key recording. Try again.',
        KeyRecordingStatus.uncertain =>
          'Key recording cleanup could not be verified.',
        KeyRecordingStatus.idle => null,
      };
      _face.value = FaceState(mood: _awake ? Mood.listening : Mood.sleepy);
    });
  }

  Future<void> _disposeKeyCapture() async {
    try {
      await _keyRecording.disposeIntent();
    } catch (_) {
      return;
    } // Do not claim or discard unresolved cleanup.
    _keyRecording.dispose();
    try {
      await _capture.dispose();
    } catch (_) {
      // Native dispose uncertainty is contained, not a successful-stop claim.
    }
  }

  Future<void> _onHoldEnd() async {
    final file = await _capture.stop();
    if (file == null) {
      // Nothing was recorded. Say why: a denied microphone and a silent room
      // look identical otherwise, and silence reads as "Bluey ignored me"
      // rather than as a permission the user can actually fix (#254).
      final denied = !await _capture.hasPermission();
      setState(() {
        _bubble = denied
            ? Strings.t(
                'I need microphone access to hear you. Allow it for Local '
                    'Bluey in System Settings, Privacy & Security, '
                    'Microphone.',
                'אני צריך גישה למיקרופון כדי לשמוע אותך. אפשר לזה בהגדרות '
                    'מערכת, פרטיות ואבטחה, מיקרופון.',
              )
            : Strings.t(
                "I didn't catch that - hold and speak a little longer.",
                'לא הצלחתי לשמוע - החזיקו ודברו מעט יותר.',
              );
        _face.value = FaceState(mood: _awake ? Mood.listening : Mood.sleepy);
      });
      return;
    }
    await _processUtterance(file);
  }

  late final RequestRunner _runner = RequestRunner(
    // No transcriber: the runner resolves the provider from the saved STT
    // settings per request, so switching provider in Settings takes effect
    // without a restart (#196).
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
    _hostReload.dispose();
    _keyRecording.removeListener(_onKeyRecordingChanged);
    _tutorial.removeListener(_onTutorialChanged);
    WidgetsBinding.instance.removeObserver(this);
    trayManager.removeListener(this);
    ScreenWatch.instance.removeListener(_syncWatchTray);
    ScreenWatch.instance.removeListener(_syncWatchDriver);
    _watchDriver?.stop();
    HoldKeySettings.instance.removeListener(_syncHoldKey);
    unawaited(_holdKey.dispose());
    _server.stop();
    _receipts.dispose();
    unawaited(_disposeKeyCapture());
    _speech.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding) {
      return Material(
        child: SafeArea(
          child: Column(
            children: [
              HostReloadNotice(controller: _hostReload),
              Expanded(
                child: OnboardingScreen(
                  onPlan: (plan) => _tutorial.configure(
                    askPrompt: plan.suggestedRequest,
                    pointing: plan.pointingAvailable,
                  ),
                  onOpenSettings: () async {
                    final saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => LockGate(
                          reason: Strings.t(
                            'Unlock Bluey settings',
                            'ביטול נעילת הגדרות Bluey',
                          ),
                          child: SettingsScreen(
                            onDeleteAll: () {
                              unawaited(_hostReload.reload());
                              if (mounted) {
                                setState(() => _showOnboarding = true);
                              }
                            },
                          ),
                        ),
                      ),
                    );
                    if (saved ?? false) unawaited(_hostReload.reload());
                  },
                  onDone: () {
                    _watchdog.recordGranted();
                    setState(() => _showOnboarding = false);
                  },
                ),
              ),
            ],
          ),
        ),
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
                  builder: (_) => LockGate(
                    reason: Strings.t(
                      'Unlock Bluey settings',
                      'ביטול נעילת הגדרות Bluey',
                    ),
                    child: SettingsScreen(
                      onDeleteAll: () {
                        unawaited(_hostReload.reload());
                        if (mounted) setState(() => _showOnboarding = true);
                      },
                    ),
                  ),
                ),
              );
              if (saved ?? false) unawaited(_hostReload.reload());
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
            if (_suggestion != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: WatchSuggestionCard(
                  suggestion: _suggestion!,
                  onDismiss: () => setState(() => _suggestion = null),
                  onNeverForApp: () async {
                    await WatchSuggestions.neverForApp(_suggestion!.app);
                    if (mounted) setState(() => _suggestion = null);
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
          HostReloadNotice(controller: _hostReload),
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
  late final _reply = PhoneReplyReceiver(
    createSession: AudioplayersReplySession.new,
    send: (packet) => _link.send(packet),
    showText: (text) {
      if (!mounted) return;
      setState(() {
        _replyText = text;
        _bubble = ReplyBubble.compose(text, _cleanupPending);
      });
    },
    isActive: () => mounted,
  );
  FaceState _face = FaceState(mood: Mood.sleepy);
  bool _connected = false;
  bool _awake = false;
  String? _bubble;
  String? _replyText;
  bool _cleanupPending = false;

  @override
  void initState() {
    super.initState();
    unawaited(RemoteHaptics.instance.loadForStartup());
    _reply.cleanupPending.addListener(_onReplyCleanup);
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
    _link.packets.listen((packet) {
      if (packet.command == 'say' && packet.text != null) {
        unawaited(RemoteHaptics.instance.fire(RemoteHapticEvent.answer));
      }
      _reply.handle(packet);
    });
    _link.start();
  }

  /// Adds or removes the short safe note; the latest answer is preserved.
  void _onReplyCleanup() {
    if (!mounted) return;
    final now = _reply.cleanupPending.value > 0;
    if (now == _cleanupPending) return;
    setState(() {
      _bubble = ReplyBubble.next(_bubble, _replyText, _cleanupPending, now);
      _cleanupPending = now;
    });
  }

  @override
  void dispose() {
    _link.stop();
    _capture.dispose();
    _reply.cleanupPending.removeListener(_onReplyCleanup);
    unawaited(_reply.dispose());
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
    _home._receipts.deliver(packet, spoken, _home._server.broadcast);
  }
}
