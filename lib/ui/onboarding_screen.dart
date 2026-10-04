import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/native_control.dart';

/// First-run permission walkthrough (macOS): Accessibility, Screen Recording,
/// Microphone, Local Network. Shown once; skippable.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  static const _kDone = 'onboarding.done';

  static Future<bool> isDone() async =>
      (await SharedPreferences.getInstance()).getBool(_kDone) ?? false;

  static Future<void> markDone() async =>
      (await SharedPreferences.getInstance()).setBool(_kDone, true);

  static const _steps = [
    (
      'Accessibility',
      'Lets Bluey point and click for you.',
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    ),
    (
      'Screen Recording',
      'Lets Bluey see what is on your screen.',
      'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
    ),
    (
      'Microphone',
      'Lets Bluey hear you while you hold to talk.',
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
    ),
    (
      'Local Network',
      'Lets your iPhone find this Mac.',
      'x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Local Bluey')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Bluey needs four macOS permissions to work. '
            'Open each panel, enable Local Bluey, then continue.',
          ),
          const SizedBox(height: 16),
          for (final (title, why, url) in _steps)
            Card(
              child: ListTile(
                title: Text(title),
                subtitle: Text(why),
                trailing: TextButton(
                  onPressed: () => NativeControl.openURL(url),
                  child: const Text('Open settings'),
                ),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              await markDone();
              onDone();
            },
            child: const Text('Done - start Bluey'),
          ),
        ],
      ),
    );
  }
}
