import 'dart:async';

import 'package:flutter/material.dart';

import '../services/biometric_lock.dart';
import '../services/strings.dart';

/// Locks [child] behind device authentication when the app lock is on (#92).
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.reason,
    required this.child,
    this.lock,
  });

  final String reason;
  final Widget child;

  /// Injected lock for deterministic tests; production uses the shared lock.
  final BiometricLock? lock;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  BiometricLock get _lock => widget.lock ?? BiometricLock.instance;
  bool _unlocked = false;
  bool _authenticating = false;
  bool _inFlight = false;
  bool _foreground = true;
  int _generation = 0;
  AuthResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  Future<void> _check() async {
    if (_inFlight || !_foreground) return;
    _inFlight = true;
    final generation = ++_generation;
    setState(() {
      _authenticating = true;
      _result = null;
    });
    final result = await _lock.requireAuth(reason: widget.reason);
    _inFlight = false;
    if (!mounted) return;
    if (generation != _generation || !_foreground) {
      setState(() {});
      return;
    }
    setState(() {
      _authenticating = false;
      _result = result;
      _unlocked = result == AuthResult.success;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_lock.enabled) return;
    if (state == AppLifecycleState.resumed) {
      setState(() => _foreground = true);
      // Resuming never creates another prompt. The user explicitly retries,
      // which avoids loops caused by native authentication lifecycle events.
      return;
    }
    if (state == AppLifecycleState.inactive && _authenticating) {
      // The native auth sheet itself can make the app inactive. Keep this
      // attempt, but gated content is already hidden while it is pending.
      return;
    }
    _foreground = false;
    ++_generation;
    setState(() {
      _unlocked = false;
      _authenticating = false;
      _result = null;
    });
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String get _message => switch (_result) {
    AuthResult.unavailable => Strings.t(
      'Device authentication is not set up. Set a device passcode or biometrics in system settings, then retry.',
      'אימות במכשיר לא הוגדר. הגדירו קוד גישה או זיהוי ביומטרי בהגדרות המערכת, ואז נסו שוב.',
    ),
    AuthResult.error => Strings.t(
      'Authentication could not start. Try again. If the problem continues, check device authentication in system settings.',
      'לא ניתן להתחיל באימות. נסו שוב. אם הבעיה נמשכת, בדקו את האימות בהגדרות המערכת.',
    ),
    AuthResult.failed => Strings.t(
      'Authentication was not completed. Bluey is still locked.',
      'האימות לא הושלם. Bluey עדיין נעול.',
    ),
    _ => Strings.t('Bluey is locked.', 'Bluey נעול.'),
  };

  @override
  Widget build(BuildContext context) {
    if (_unlocked || !_lock.enabled) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (_authenticating)
                    Semantics(
                      label: Strings.t('Authenticating', 'מתבצע אימות'),
                      child: const CircularProgressIndicator(),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _foreground && !_inFlight ? _check : null,
                      icon: const Icon(Icons.lock_open),
                      label: Text(Strings.t('Unlock', 'ביטול נעילה')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
