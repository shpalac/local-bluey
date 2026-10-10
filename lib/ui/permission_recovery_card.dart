import 'package:flutter/material.dart';

import '../services/native_control.dart';
import '../services/onboarding_checks.dart';
import '../services/strings.dart';

/// Responsive recovery for a revoked permission; Fix is explicit user action.
class PermissionRecoveryCard extends StatefulWidget {
  const PermissionRecoveryCard({
    super.key,
    required this.permission,
    required this.onDismiss,
    this.fix,
  });

  /// Revoked permission and its localized explanation.
  final OnboardingPermission permission;

  /// Dismisses this notice.
  final VoidCallback onDismiss;

  /// Fixture seam; production requests access then opens System Settings.
  final Future<void> Function()? fix;
  @override
  State<PermissionRecoveryCard> createState() => _PermissionRecoveryCardState();
}

class _PermissionRecoveryCardState extends State<PermissionRecoveryCard> {
  bool _fixing = false;
  bool _failed = false;
  Future<void> _fix() async {
    if (_fixing) return;
    setState(() {
      _fixing = true;
      _failed = false;
    });
    try {
      if (widget.fix != null) {
        await widget.fix!();
      } else {
        // Register first so the OS pane contains Bluey's Screen Recording row.
        if (widget.permission.id == 'screen_recording') {
          await NativeControl.requestScreenCaptureAccess();
          if (!mounted) return;
        }
        final result = await NativeControl.openURL(
          widget.permission.settingsUrl,
        );
        // The bridge reports failures as strings, not only platform exceptions.
        // Its current success result is "Opened <host>."; settings schemes
        // are unsupported. Fail closed on null/unrecognized results too.
        if (result == null || !result.startsWith('Opened ')) {
          if (mounted) setState(() => _failed = true);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _fixing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = widget.permission;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    Strings.t(
                      '${p.localTitle} was revoked',
                      'ההרשאה ${p.localTitle} בוטלה',
                    ),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(p.localWhy, style: TextStyle(color: scheme.onErrorContainer)),
            if (_failed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  Strings.t(
                    'Could not open permission settings. Try again or open System Settings.',
                    'לא ניתן לפתוח את הגדרות ההרשאה. נסו שוב או פתחו את הגדרות המערכת.',
                  ),
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _fixing ? null : _fix,
                  child: Text(
                    Strings.t(
                      _fixing ? 'Opening settings...' : 'Fix',
                      _fixing ? 'פותח הגדרות...' : 'תיקון',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onDismiss,
                  child: Text(Strings.t('Later', 'מאוחר יותר')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
