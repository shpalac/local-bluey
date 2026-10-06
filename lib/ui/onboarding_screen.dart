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

  /// Re-checks the current permission alone. A grant marks the step done
  /// and advances; a deny stays put and says so. Overlapping calls are
  /// ignored, and a result that arrives after Back/Skip is discarded.
  Future<void> _verify() async {
    if (_busy) return;
    final id = _current.id;
    final title = _current.title;
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
    if (error != null || granted == null) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$title is still off - open Settings, grant it, '
            'then verify again.',
          ),
        ),
      );
      return;
    }
    await OnboardingScreen._markStepDone(id, true);
    if (_disposed || !mounted || gen != _gen) return;
    await _advance();
  }

  Future<void> _advance() async {
    if (_last) {
      await _finish();
    } else {
      _gen++;
      setState(() => _step++);
    }
  }

  /// Skipping is only for permissions the first answer does not need (#86).
  Future<void> _skip() async {
    if (_busy) return;
    await OnboardingScreen._markStepDone(_current.id, true);
    if (_disposed || !mounted) return;
    await _advance();
  }

  void _back() {
    if (_busy) return;
    _gen++;
    setState(() => _step--);
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

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    var micOk = true;
    try {
      micOk = await requiredGranted(widget.checker);
    } catch (_) {
      micOk = false;
    }
    if (_disposed || !mounted) return;
    if (!micOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Microphone is still missing or could not be checked - the '
            'first spoken answer needs it. You can finish anyway and grant '
            'it later.',
          ),
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final p = _current;
    final granted = _granted[p.id];
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Local Bluey')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Step ${_step + 1} of ${onboardingPermissions.length}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                title: Text(p.title),
                subtitle: Text(p.why),
                leading: _failed.containsKey(p.id)
                    ? const Icon(Icons.error_outline)
                    : _notCheckable.contains(p.id)
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
                FilledButton(
                  onPressed: _openSettings,
                  child: const Text('Open Settings'),
                ),
                if (!_notCheckable.contains(p.id))
                  OutlinedButton(
                    onPressed: _busy ? null : _verify,
                    child: const Text('Verify'),
                  ),
                if (!p.requiredForFirstAnswer)
                  TextButton(
                    onPressed: _busy ? null : _skip,
                    child: const Text('Skip'),
                  ),
                if (_step > 0)
                  TextButton(
                    onPressed: _busy ? null : _back,
                    child: const Text('Back'),
                  ),
              ],
            ),
            const Spacer(),
            const Text('Then hold the face and ask: "what\'s on my screen?"'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _finish,
              child: const Text('Done - start Bluey'),
            ),
          ],
        ),
      ),
    );
  }
}
