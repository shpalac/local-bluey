import 'package:flutter/material.dart';

import '../services/biometric_lock.dart';
import '../services/strings.dart';

/// App-lock preference. Enabling must authenticate before it is persisted.
class AppLockTile extends StatefulWidget {
  const AppLockTile({super.key, this.lock});

  /// Injected service for deterministic widget fixtures.
  final BiometricLock? lock;

  @override
  State<AppLockTile> createState() => _AppLockTileState();
}

class _AppLockTileState extends State<AppLockTile> {
  BiometricLock get _lock => widget.lock ?? BiometricLock.instance;
  bool _saving = false;
  AuthResult? _result;

  Future<void> _change(bool value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _result = null;
    });
    final result = await _lock.setEnabled(
      value,
      reason: Strings.t('Enable Bluey app lock', 'הפעלת נעילת Bluey'),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _result = result;
    });
  }

  String get _description => switch (_result) {
    AuthResult.unavailable => Strings.t(
      'App lock was not enabled. Set up a device passcode or biometrics in system settings and try again.',
      'נעילת האפליקציה לא הופעלה. הגדירו קוד גישה או זיהוי ביומטרי בהגדרות המערכת ונסו שוב.',
    ),
    AuthResult.error => Strings.t(
      'Could not save app lock. Try again and check device authentication in system settings.',
      'לא ניתן לשמור את נעילת האפליקציה. נסו שוב ובדקו את האימות בהגדרות המערכת.',
    ),
    AuthResult.failed => Strings.t(
      'App lock was not enabled because authentication was not completed.',
      'נעילת האפליקציה לא הופעלה כי האימות לא הושלם.',
    ),
    _ => Strings.t(
      'Require device biometrics or passcode for the remote and Settings.',
      'דרישת זיהוי ביומטרי או קוד גישה לשלט ולהגדרות.',
    ),
  };

  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: const Icon(Icons.lock_outline),
    title: Text(Strings.t('App lock', 'נעילת אפליקציה')),
    subtitle: Text(_description),
    value: _lock.enabled,
    onChanged: _saving ? null : _change,
  );
}
