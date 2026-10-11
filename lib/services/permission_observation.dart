import 'dart:async';

import 'package:flutter/foundation.dart';

import 'onboarding_checks.dart';
import 'permission_watchdog.dart';

/// Read-only recovery observation, never a grant or deletion guarantee.
enum PermissionObservationStatus { unknown, loading, current, failed }

/// Coalesces explicit checks and remembers a fresh read requested by resume.
/// One shared completion covers the entered read and its coalesced successors.
class PermissionObservation extends ChangeNotifier {
  PermissionObservation({
    required this.watchdog,
    Future<List<OnboardingPermission>> Function()? read,
  }) : _read = read ?? watchdog.recheckRevoked;

  final PermissionWatchdog watchdog;

  final Future<List<OnboardingPermission>> Function() _read;
  PermissionObservationStatus _status = PermissionObservationStatus.unknown;
  List<OnboardingPermission> _revoked = [];
  final Map<String, int> _dismissals = {};
  bool _disposed = false, _notifierDisposed = false;
  bool _entered = false, _fresh = false;
  int _notifyDepth = 0;
  Future<void>? _pending;

  PermissionObservationStatus get status => _status;

  /// Retained recovery list; not current permission proof during loading/error.
  List<OnboardingPermission> get revoked => List.unmodifiable(_revoked);

  /// Display-only invalidation at the existing selected-id dismissal path.
  /// The caller does not clear persistence; main keeps that owner side effect.
  void dismiss(String id) {
    if (_disposed) return;
    _dismissals[id] = (_dismissals[id] ?? 0) + 1;
    _revoked = _revoked.where((p) => p.id != id).toList();
    _publish();
  }

  bool get loading => _status == PermissionObservationStatus.loading;

  /// Startup and deliberate retry share an installed pending completion.
  Future<void> check() {
    if (_disposed) return Future<void>.value();
    final pending = _pending;
    if (pending != null) return pending;
    final done = Completer<void>();
    _pending = done.future;
    _status = PermissionObservationStatus.loading;
    scheduleMicrotask(() => _run(done));
    _publish();
    return done.future;
  }

  /// Bursts while one read is entered request at most one fresh successor.
  /// The returned completion waits through that successor. A resume before
  /// source entry joins the still-fresh queued read rather than adding one.
  Future<void> resume() {
    if (_disposed) return Future<void>.value();
    if (_pending != null && _entered) _fresh = true;
    return check();
  }

  Future<void> _run(Completer<void> done) async {
    while (!_disposed) {
      _fresh = false;
      _entered = true;
      final observed = Map<String, int>.of(_dismissals);
      List<OnboardingPermission>? value;
      var failed = false;
      try {
        value = await _read();
      } catch (_) {
        failed = true;
      }
      _entered = false;
      if (_disposed) break;
      if (_fresh) continue; // No publication of superseded observations.
      if (failed) {
        _status = PermissionObservationStatus.failed;
      } else {
        _revoked = value!
            .where((p) => (observed[p.id] ?? 0) == (_dismissals[p.id] ?? 0))
            .toList();
        _status = PermissionObservationStatus.current;
      }
      break;
    }
    _pending = null;
    if (!_disposed) _publish();
    done.complete();
  }

  void _publish() {
    _notifyDepth++;
    try {
      notifyListeners();
    } finally {
      _notifyDepth--;
      if (_disposed && _notifyDepth == 0 && !_notifierDisposed) {
        _notifierDisposed = true;
        super.dispose();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fresh = false;
    if (_notifyDepth == 0 && !_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}
