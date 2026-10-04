import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/native_control.dart';
import '../services/onboarding_checks.dart';

/// First-run permission walkthrough (#86): live status per permission,
/// re-checked when the app regains focus; lazy requests keep the minimal
/// path to a first answer short. Re-enterable from Settings (#85).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.checker = const LivePermissionChecker(),
  });

  final VoidCallback onDone;
  final PermissionChecker checker;

  static const _kDone = 'onboarding.done';

  static Future<bool> isDone() async =>
      (await SharedPreferences.getInstance()).getBool(_kDone) ?? false;

  static Future<void> markDone() async =>
      (await SharedPreferences.getInstance()).setBool(_kDone, true);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final _granted = <String, bool?>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Local Bluey')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Bluey asks for each permission only when its feature is first '
            'used. Microphone is enough for your first spoken answer.',
          ),
          const SizedBox(height: 16),
          for (final p in onboardingPermissions)
            Card(
              child: ListTile(
                title: Text(p.title),
                subtitle: Text(p.why),
                leading: switch (_granted[p.id]) {
                  true => const Icon(Icons.check_circle, color: Colors.green),
                  false => const Icon(Icons.radio_button_off),
                  null => const Icon(Icons.hourglass_top),
                },
                trailing: TextButton(
                  onPressed: () => NativeControl.openURL(p.settingsUrl),
                  child: Text(_granted[p.id] == true ? 'Granted' : 'Open'),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text('Then hold the face and ask: "what\'s on my screen?"'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _finish,
            child: const Text('Done - start Bluey'),
          ),
        ],
      ),
    );
  }
}
