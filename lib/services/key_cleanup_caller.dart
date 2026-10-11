import 'package:flutter/foundation.dart';

import 'key_recording_intent.dart';

/// Explicit cleanup observation only, never recording or request state.
class KeyCleanupCaller extends ChangeNotifier {
  KeyCleanupCaller({required this.owner, bool Function()? allowed})
    : _allowed = allowed ?? (() => true) {
    owner.addListener(_ownerChanged);
  }
  final KeyRecordingIntent owner;
  final bool Function() _allowed;
  bool _disposed = false, _notifierDisposed = false;
  int _notifyDepth = 0, _evidenceGeneration = 0;
  bool _invokingRecovery = false;
  bool _loading = false, _failed = false;
  Future<void>? _pending;

  bool get loading => _loading;
  bool get failed => _failed;
  bool get eligible =>
      owner.cleanupPending &&
      (owner.status == KeyRecordingStatus.failed ||
          owner.status == KeyRecordingStatus.uncertain ||
          (_failed && owner.status == KeyRecordingStatus.pending));
  bool get visible => !_disposed && (_loading || eligible);
  bool get enabled => !_disposed && !_loading && eligible && _allowed();

  void _ownerChanged() {
    if (!_invokingRecovery && owner.status == KeyRecordingStatus.pending) {
      _evidenceGeneration++;
      _failed = false;
    }
    if (!owner.cleanupPending ||
        owner.status == KeyRecordingStatus.listening ||
        owner.status == KeyRecordingStatus.idle) {
      _failed = false;
    }
    if (!_disposed && _allowed()) _publish();
  }

  /// Guard changes never trigger recovery. Used by host kill/lifecycle state.
  void refreshGuard() {
    if (!_disposed) _publish();
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

  /// Only deliberate currently eligible calls enter recovery. Pending callers
  /// join through actual stop/delete completion even if allowed becomes false.
  Future<void> retry() {
    if (_disposed) return Future<void>.value();
    final pending = _pending;
    if (pending != null) return pending;
    if (!enabled) return Future<void>.value();
    final op = Future<void>.microtask(_run);
    _pending = op;
    _loading = true;
    _publish();
    op.then((_) {
      if (identical(_pending, op)) _pending = null;
    });
    return op;
  }

  Future<void> _run() async {
    if (_disposed) return;
    final generation = _evidenceGeneration;
    var failed = true;
    if (_allowed() && eligible) {
      try {
        _invokingRecovery = true;
        final recovery = owner.recover(
          canEnter: () =>
              !_disposed && _allowed() && generation == _evidenceGeneration,
        );
        _invokingRecovery = false;
        await recovery;
        failed = false;
      } catch (_) {
        failed = true;
      } finally {
        _invokingRecovery = false;
      }
    }
    if (_disposed) return;
    // Always settle observation, even after kill during entered cleanup.
    _loading = false;
    _failed =
        failed && generation == _evidenceGeneration && owner.cleanupPending;
    if (_allowed() && generation == _evidenceGeneration) _publish();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loading = false;
    owner.removeListener(_ownerChanged);
    if (_notifyDepth == 0 && !_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}
