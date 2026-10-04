import 'package:flutter/material.dart';

import '../services/biometric_lock.dart';

/// Locks [child] behind device authentication when the app lock is on (#92).
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.reason, required this.child});

  final String reason;
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  bool _unlocked = false;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final result = await BiometricLock.instance.requireAuth(
      reason: widget.reason,
    );
    if (!mounted) return;
    setState(() {
      _unlocked = result == AuthResult.success;
      _unavailable = result == AuthResult.unavailable;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              _unavailable
                  ? 'Authentication is unavailable on this device.'
                  : 'Bluey is locked.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (!_unavailable)
              FilledButton.icon(
                onPressed: _check,
                icon: const Icon(Icons.lock_open),
                label: const Text('Unlock'),
              ),
          ],
        ),
      ),
    );
  }
}
