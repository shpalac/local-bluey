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
  final _granted = <String, bool?>{};
  int _step = 0;

  OnboardingPermission get _current => onboardingPermissions[_step];
  bool get _last => _step == onboardingPermissions.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OnboardingScreen.firstUnfinishedStep().then((step) {
      if (mounted) setState(() => _step = step);
    });
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from system Settings re-checks everything (#86).
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final c = widget.checker;
    final statuses = <String, bool?>{
      'accessibility': await c.accessibility(),
      'screen_recording': await c.screenRecording(),
      'microphone': await c.microphone(),
      'local_network': await c.localNetwork(),
    };
    if (mounted) setState(() => _granted.addAll(statuses));
  }

  /// Re-checks the current permission alone. A grant marks the step done
  /// and advances; a deny stays put and says so.
  Future<void> _verify() async {
    final c = widget.checker;
    final granted = await switch (_current.id) {
      'accessibility' => c.accessibility(),
      'screen_recording' => c.screenRecording(),
      'microphone' => c.microphone(),
      _ => c.localNetwork(),
    };
    if (!mounted) return;
    setState(() => _granted[_current.id] = granted);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_current.title} is still off - open Settings, grant it, '
            'then verify again.',
          ),
        ),
      );
      return;
    }
    await OnboardingScreen._markStepDone(_current.id, true);
    if (!mounted) return;
    if (_last) {
      await _finish();
    } else {
      setState(() => _step++);
    }
  }

  /// Skipping is only for permissions the first answer does not need (#86).
  Future<void> _skip() async {
    await OnboardingScreen._markStepDone(_current.id, true);
    if (!mounted) return;
    if (_last) {
      await _finish();
    } else {
      setState(() => _step++);
    }
  }

  Future<void> _finish() async {
    if (!await requiredGranted(widget.checker)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone is still missing - the first spoken answer needs '
              'it. You can finish anyway and grant it later.',
            ),
          ),
        );
      }
    }
    await OnboardingScreen.markDone();
    widget.onDone();
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
                leading: switch (granted) {
                  true => const Icon(Icons.check_circle, color: Colors.green),
                  false => const Icon(Icons.radio_button_off),
                  null => const Icon(Icons.hourglass_top),
                },
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => NativeControl.openURL(p.settingsUrl),
                  child: const Text('Open Settings'),
                ),
                OutlinedButton(onPressed: _verify, child: const Text('Verify')),
                if (!p.requiredForFirstAnswer)
                  TextButton(onPressed: _skip, child: const Text('Skip')),
                if (_step > 0)
                  TextButton(
                    onPressed: () => setState(() => _step--),
                    child: const Text('Back'),
                  ),
              ],
            ),
            const Spacer(),
            const Text('Then hold the face and ask: "what\'s on my screen?"'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _finish,
              child: const Text('Done - start Bluey'),
            ),
          ],
        ),
      ),
    );
  }
}
