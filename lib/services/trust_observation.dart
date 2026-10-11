import 'dart:async';

import 'package:flutter/foundation.dart';

import 'host_control.dart';

/// Read-only Accessibility observation, never permission authorization.
enum TrustObservationStatus { unknown, loading, granted, denied, failed }

/// Coalesces explicit checks and remembers a fresh read requested by resume.
/// One shared completion covers the entered read and its coalesced successors.
class TrustObservation extends ChangeNotifier {
  TrustObservation({Future<bool> Function()? read})
    : _read = read ?? (() => HostControl.forPlatform().isTrusted());

  final Future<bool> Function() _read;
  TrustObservationStatus _status = TrustObservationStatus.unknown;
  bool? _lastObservation;
  bool _disposed = false, _notifierDisposed = false;
  bool _entered = false, _fresh = false;
  int _notifyDepth = 0;
  Future<void>? _pending;

  TrustObservationStatus get status => _status;

  /// Historical observation only; not current grant proof during loading/error.
  bool? get lastObservation => _lastObservation;
  bool get loading => _status == TrustObservationStatus.loading;

  /// Startup and deliberate retry share an installed pending completion.
  Future<void> check() {
    if (_disposed) return Future<void>.value();
    final pending = _pending;
    if (pending != null) return pending;
    final done = Completer<void>();
    _pending = done.future;
    _status = TrustObservationStatus.loading;
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
      bool? value;
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
        _status = TrustObservationStatus.failed;
      } else {
        _lastObservation = value;
        _status = value!
            ? TrustObservationStatus.granted
            : TrustObservationStatus.denied;
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
