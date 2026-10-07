import 'package:flutter/material.dart';

import '../services/native_control.dart';
import '../services/onboarding_checks.dart';

/// One-tap recovery when a previously granted permission is found revoked
/// (#174): explains what broke and deep-links straight to the right
/// System Settings pane.
class PermissionRecoveryCard extends StatelessWidget {
  const PermissionRecoveryCard({
    super.key,
    required this.permission,
    required this.onDismiss,
  });

  final OnboardingPermission permission;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.warning_amber, color: scheme.onErrorContainer),
        title: Text(
          '${permission.title} was revoked',
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        subtitle: Text(
          permission.why,
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () async {
                // Registering first is what puts Bluey in the Screen Recording
                // list; opening the pane alone shows an empty page (#124).
                // Tapping "Fix" is the consent the system prompt asks about.
                if (permission.id == 'screen_recording') {
                  await NativeControl.requestScreenCaptureAccess();
                }
                await NativeControl.openURL(permission.settingsUrl);
              },
              child: const Text('Fix'),
            ),
            TextButton(onPressed: onDismiss, child: const Text('Later')),
          ],
        ),
      ),
    );
  }
}
