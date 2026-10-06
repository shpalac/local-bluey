import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/native_control.dart';
import '../services/onboarding_checks.dart';

/// First-run permission walkthrough, one permission per step (#174):
/// plain-language why, a verify button that re-checks the real grant, and
/// a deep link to the right System Settings pane. Progress persists per
/// step, so a returning user lands on the first unfinished step. The app
/// re-checks grants on resume; revocations surface as a recovery card in
/// the main window (PermissionWatchdog + PermissionRecoveryCard).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.checker = const LivePermissionChecker(),
  });

  final VoidCallback onDone;
  final PermissionChecker checker;

  static const _kDone = 'onboarding.done';
  static const _kStepPrefix = 'onboarding.step.';
  static const _kDeferredPrefix = 'onboarding.deferred.';

  /// Permission ids the user chose to set up later (#224). Kept apart from
  /// the step-reviewed flag so navigation progress never reads as a grant.
  static Future<Set<String>> deferredSteps() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final p in onboardingPermissions)
        if (prefs.getBool('$_kDeferredPrefix${p.id}') ?? false) p.id,
    };
  }

  static Future<void> _setDeferred(String id, bool deferred) async =>
      (await SharedPreferences.getInstance()).setBool(
        '$_kDeferredPrefix$id',
        deferred,
      );

  static Future<bool> isDone() async =>
      (await SharedPreferences.getInstance()).getBool(_kDone) ?? false;

  static Future<void> markDone() async =>
      (await SharedPreferences.getInstance()).setBool(_kDone, true);

  static Future<void> _markStepDone(String id, bool done) async =>
      (await SharedPreferences.getInstance()).setBool('$_kStepPrefix$id', done);

  /// First step without a persisted completion, or the last step when every
  /// one is done (a returning user reviews the final step, not a blank end).
  static Future<int> firstUnfinishedStep() async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < onboardingPermissions.length; i++) {
      if (!(prefs.getBool('$_kStepPrefix${onboardingPermissions[i].id}') ??
          false)) {
        return i;
      }
    }
    return onboardingPermissions.length - 1;
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  /// Permissions with no OS preflight: their state is unknown, never denied.
  static const _notCheckable = {'local_network'};

  final _granted = <String, bool?>{};
  final _failed = <String, String>{};
  Set<String> _deferred = {};
  bool _summary = false;
  int _step = 0;
  bool _busy = false;
  bool _disposed = false;

  /// Bumped on every step change and disposal. A verify result that finds a
  /// different generation than it started with is stale and dropped.
  int _gen = 0;

  /// Bumped on each refresh and disposal; only the newest refresh applies.
  int _refreshGen = 0;

  OnboardingPermission get _current => onboardingPermissions[_step];
  bool get _last => _step == onboardingPermissions.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OnboardingScreen.firstUnfinishedStep().then((step) {
      if (mounted) {
        _gen++;
        setState(() => _step = step);
      }
    });
    OnboardingScreen.deferredSteps().then((d) {
      if (mounted) setState(() => _deferred = d);
    });
    _refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _refreshGen++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from system Settings re-checks everything (#86).
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// One check by permission id. Returns null when the state cannot be
  /// known (no preflight) and throws when the native check fails.
  Future<bool?> _check(String id) {
    final c = widget.checker;
    return switch (id) {
      'accessibility' => c.accessibility(),
      'screen_recording' => c.screenRecording(),
      'microphone' => c.microphone(),
      _ => Future<bool?>.value(null),
    };
  }

  Future<void> _refresh() async {
    final gen = ++_refreshGen;
    // Each permission is checked on its own so one failing native call
    // cannot hide the others' results.
    final statuses = <String, bool?>{};
    final errors = <String, String>{};
    for (final p in onboardingPermissions) {
      if (_notCheckable.contains(p.id)) {
        statuses[p.id] = null;
        continue;
      }
      try {
        statuses[p.id] = await _check(p.id);
      } catch (e) {
        errors[p.id] = '$e';
      }
    }
    if (_disposed || !mounted || gen != _refreshGen) return;
    setState(() {
      _granted.addAll(statuses);
      for (final id in statuses.keys) {
        _failed.remove(id);
      }
      _failed.addAll(errors);
    });
  }

  /// Re-checks the current permission alone. A grant only updates the
  /// status; the user moves on with Continue. Overlapping calls are ignored,
  /// and a result that arrives after Back/Later is discarded.
  Future<void> _verify() async {
    if (_busy) return;
    final id = _current.id;
    final gen = ++_gen;
    setState(() => _busy = true);
    bool? granted;
    String? error;
    try {
      granted = await _check(id);
    } catch (e) {
      error = '$e';
    }
    if (_disposed || !mounted) return;
    if (gen != _gen) {
      // The user moved on while the check ran; it must not touch this step.
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = false;
      if (error != null) {
        _failed[id] = error;
      } else {
        _failed.remove(id);
        _granted[id] = granted;
      }
    });
    if (error == null && granted == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_current.title} is still off - open Settings, grant it, '
            'then check again.',
          ),
        ),
      );
    }
  }

  /// Moves past the current step. [deferred] records a "set up later"
  /// choice; a granted step clears any earlier deferral.
  Future<void> _next({required bool deferred}) async {
    if (_busy) return;
    final id = _current.id;
    await OnboardingScreen._markStepDone(id, true);
    await OnboardingScreen._setDeferred(id, deferred);
    if (_disposed || !mounted) return;
    setState(() {
      deferred ? _deferred.add(id) : _deferred.remove(id);
    });
    if (_last) {
      _gen++;
      setState(() => _summary = true);
    } else {
      _gen++;
      setState(() => _step++);
    }
  }

  void _back() {
    if (_busy) return;
    _gen++;
    setState(() => _step--);
  }

  void _jumpTo(int step) {
    if (_busy || step == _step) return;
    _gen++;
    setState(() => _step = step);
  }

  Future<void> _openSettings() async {
    final id = _current.id;
    String? error;
    try {
      final result = await NativeControl.openURL(_current.settingsUrl);
      if (result == null || !result.startsWith('Opened')) {
        error = result ?? 'no response';
      }
    } catch (e) {
      error = '$e';
    }
    if (_disposed || !mounted) return;
    setState(() {
      if (error != null) {
        _failed['$id.settings'] = error;
      } else {
        _failed.remove('$id.settings');
      }
    });
  }

  /// Leaving early opens the summary; nothing is marked done until the
  /// user confirms there with the consequences in view.
  void _finishLater() {
    if (_busy) return;
    _gen++;
    setState(() => _summary = true);
  }

  Future<void> _startBluey() async {
    if (_busy) return;
    await OnboardingScreen.markDone();
    widget.onDone();
  }

  String _stateLine(OnboardingPermission p) {
    if (_failed.containsKey(p.id)) {
      return 'Could not check this permission. Try Verify again, or open '
          'System Settings > Privacy & Security and look for ${p.title}.';
    }
    if (_notCheckable.contains(p.id)) {
      return 'macOS only asks for this when your iPhone first looks for '
          'this Mac, so it cannot be checked here. Skip it now and approve '
          'the prompt when you pair the phone.';
    }
    return switch (_granted[p.id]) {
      true => 'Granted.',
      false => 'Not granted yet.',
      null => 'Checking...',
    };
  }

  /// What stays off when a permission is not granted (#224).
  static const _consequence = {
    'accessibility': 'Bluey cannot click or type for you.',
    'screen_recording': 'Bluey cannot see what is on your screen.',
    'microphone': 'Bluey cannot hear you, so spoken questions will not work.',
    'local_network': 'Your iPhone cannot find this Mac until you approve it.',
  };

  static const _laterLabel = {
    'accessibility': 'Set up click control later',
    'screen_recording': 'Set up screen access later',
    'local_network': 'Set up phone pairing later',
  };

  /// One display state per step: granted, deferred, unknown or missing.
  String _stateOf(OnboardingPermission p) {
    if (_granted[p.id] == true) return 'granted';
    if (_deferred.contains(p.id)) return 'deferred';
    if (_notCheckable.contains(p.id)) return 'unknown';
    return 'missing';
  }

  Widget _overview(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (var i = 0; i < onboardingPermissions.length; i++)
          ChoiceChip(
            key: Key('step-${onboardingPermissions[i].id}'),
            selected: i == _step,
            avatar: Icon(switch (_stateOf(onboardingPermissions[i])) {
              'granted' => Icons.check_circle,
              'deferred' => Icons.schedule,
              'unknown' => Icons.help_outline,
              _ => Icons.radio_button_unchecked,
            }, size: 18),
            label: Text(
              '${onboardingPermissions[i].title} - '
              '${switch (_stateOf(onboardingPermissions[i])) {
                'granted' => 'granted',
                'deferred' => 'later',
                'unknown' => 'asked at pairing',
                _ => 'not granted',
              }}',
            ),
            onSelected: (_) => _jumpTo(i),
          ),
      ],
    );
  }

  Widget _summaryView(BuildContext context) {
    final rows = <Widget>[];
    for (final p in onboardingPermissions) {
      final state = _stateOf(p);
      rows.add(
        ListTile(
          key: Key('summary-${p.id}'),
          leading: Icon(
            state == 'granted' ? Icons.check_circle : Icons.info_outline,
          ),
          title: Text(p.title),
          subtitle: Text(
            state == 'granted' ? 'Available.' : _consequence[p.id]!,
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Setup summary')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You can change any of these later in System Settings. '
              'Bluey tells you when a missing permission blocks something.',
            ),
            const SizedBox(height: 8),
            Expanded(child: ListView(children: rows)),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _gen++;
                          setState(() => _summary = false);
                        },
                  child: const Text('Back to setup'),
                ),
                FilledButton(
                  onPressed: _busy ? null : _startBluey,
                  child: const Text('Start Bluey'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_summary) return _summaryView(context);
    final p = _current;
    final granted = _granted[p.id];
    final failed = _failed.containsKey(p.id);
    final notCheckable = _notCheckable.contains(p.id);
    // One primary action per state.
    final Widget primary;
    if (granted == true || notCheckable) {
      primary = FilledButton(
        onPressed: _busy ? null : () => _next(deferred: notCheckable),
        child: Text(_last ? 'Continue to summary' : 'Continue'),
      );
    } else if (granted == null && !failed) {
      primary = const FilledButton(onPressed: null, child: Text('Checking...'));
    } else {
      primary = FilledButton(
        onPressed: _openSettings,
        child: const Text('Open Settings'),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Local Bluey')),
      // One focused panel: centred, width-bounded, scrolls when it cannot
      // fit (compact windows, large text) instead of overflowing (#223).
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Set up ${p.title}',
                  style: Theme.of(context).textTheme.headlineSmall,
                  semanticsLabel: 'Set up ${p.title}',
                ),
                const SizedBox(height: 16),
                _overview(context),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: Text(p.title),
                    subtitle: Text(p.why),
                    leading: failed
                        ? const Icon(Icons.error_outline)
                        : notCheckable
                        ? const Icon(Icons.help_outline)
                        : switch (granted) {
                            true => const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                            false => const Icon(Icons.radio_button_off),
                            null => const Icon(Icons.hourglass_top),
                          },
                  ),
                ),
                const SizedBox(height: 8),
                Text(_stateLine(p), key: const Key('onboarding-state')),
                if (_failed.containsKey('${p.id}.settings'))
                  const Text(
                    'Could not open System Settings. Open it yourself: '
                    'Privacy & Security, then pick this permission.',
                    key: Key('onboarding-settings-error'),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    primary,
                    if (!notCheckable && granted != true)
                      OutlinedButton(
                        onPressed: _busy ? null : _verify,
                        child: const Text('Check again'),
                      ),
                    if (!p.requiredForFirstAnswer &&
                        granted != true &&
                        !notCheckable)
                      TextButton(
                        onPressed: _busy ? null : () => _next(deferred: true),
                        child: Text(_laterLabel[p.id] ?? 'Set up later'),
                      ),
                    if (_step > 0)
                      TextButton(
                        onPressed: _busy ? null : _back,
                        child: const Text('Back'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _busy ? null : _finishLater,
                  child: const Text('Finish setup later'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
