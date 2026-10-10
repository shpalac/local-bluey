// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'audio_capture.dart';

/// Key recorder intent observation, not native microphone readiness.
enum KeyRecordingStatus {
  pending,
  listening,
  denied,
  empty,
  idle,
  failed,
  uncertain,
}

/// Safe current key intent failure; unresolved cleanup remains owned.
class KeyRecordingException implements Exception {
  /// Creates a generic failure.
  const KeyRecordingException();
  @override
  String toString() => 'Could not finish key recording. Try again.';
}

/// Orders key-only capture effects and retains uncertain stop/file cleanup.
/// Other input sources sharing the capture are outside this owner's scope.
class KeyRecordingIntent extends ChangeNotifier {
  /// Uses actual AudioCapture operations by default or injected effects.
  // Public named operation seams keep existing capture injection explicit.
  KeyRecordingIntent({
    required AudioCapture capture,
    required Future<void> Function(File) deliver,
    bool Function()? allowed,
    Future<void> Function(File)? delete,
  }) : _capture = capture,
       _deliver = deliver,
       _allowed = allowed ?? (() => true),
       _delete =
           delete ??
           ((file) async {
             if (await file.exists()) await file.delete();
           });
  final AudioCapture _capture;
  final Future<void> Function(File) _deliver;
  final bool Function() _allowed;
  final Future<void> Function(File) _delete;
  Future<void>? _tail;
  Future<void>? _close;
  bool _closeFailed = false;
  int _session = 0;
  bool _ended = true, _disposed = false;
  CaptureAcquisition? _acquisition;
  Future<void>? _recovery;
  bool _captureUncertain = false;
  File? _pendingFile;
  KeyRecordingStatus _status = KeyRecordingStatus.idle;

  /// Current intent observation, not confirmed native recording state.
  KeyRecordingStatus get status => _status;

  /// Unresolved entered capture stop or file deletion is retained for retry.
  bool get cleanupPending =>
      _captureUncertain || _acquisition != null || _pendingFile != null;

  bool _current(int session) => !_disposed && session == _session && _allowed();
  void _publish(int session, KeyRecordingStatus value) {
    if (!_current(session)) return;
    _status = value;
    notifyListeners();
  }

  Future<void> _enqueue(int session, Future<void> Function() action) {
    final next = (_tail ?? Future<void>.value()).then((_) async {
      try {
        await action();
      } catch (_) {
        _publish(
          session,
          _captureUncertain
              ? KeyRecordingStatus.uncertain
              : KeyRecordingStatus.failed,
        );
        throw const KeyRecordingException();
      }
    });
    final settled = next.catchError((_) {});
    _tail = settled;
    settled.then((_) {
      if (identical(_tail, settled)) _tail = null;
    });
    return next;
  }

  Future<void> _deletePending() async {
    final file = _pendingFile;
    if (file == null) return;
    await _delete(file);
    if (identical(_pendingFile, file)) _pendingFile = null;
  }

  Future<File?> _stopOwned() async {
    if (_captureUncertain) throw const KeyRecordingException();
    if (_pendingFile != null) return _pendingFile;
    final identity = _acquisition;
    if (identity == null) return null;
    try {
      final result = await _capture.release(identity);
      if (!_settled(result.outcome)) throw const KeyRecordingException();
      if (identical(identity, _acquisition)) {
        _pendingFile = result.file;
        if (result.file == null) _acquisition = null;
      }
      return result.file;
    } catch (_) {
      _captureUncertain = true;
      rethrow;
    }
  }

  bool _settled(CaptureCleanupOutcome outcome) =>
      outcome == CaptureCleanupOutcome.cleaned ||
      outcome == CaptureCleanupOutcome.noDriverEntry ||
      outcome == CaptureCleanupOutcome.transferred;

  Future<void> _cleanup({bool explicit = false}) async {
    if (_captureUncertain && !explicit) throw const KeyRecordingException();
    final identity = _acquisition;
    if (identity != null) {
      try {
        final result = await _capture.cleanup(identity);
        if (!_settled(result)) throw const KeyRecordingException();
      } catch (_) {
        _captureUncertain = true;
        rethrow;
      }
    }
    // A transferred capture receipt never authorizes deletion of external
    // output. Only this key owner's separately retained File is deleted.
    await _deletePending();
    if (identical(identity, _acquisition)) {
      _acquisition = null;
      _captureUncertain = false;
    }
  }

  /// Dedicated explicit no-delivery recovery. Fresh holds never call this.
  /// Concurrent calls join installed completion through stop/file deletion.
  /// Resource cleanup can finish after kill/cancel, but only current allowed
  /// generation publishes. Disposed owners cannot be revived.
  Future<void> recover() {
    if (_disposed) return Future<void>.value();
    final pending = _recovery;
    if (pending != null) return pending;
    final session = _session;
    final op = _enqueue(session, () async {
      await _cleanup(explicit: true);
      _publish(session, KeyRecordingStatus.idle);
    });
    _recovery = op;
    final settled = op.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    settled.then((_) {
      if (identical(_recovery, op)) _recovery = null;
    });
    // Installed first: a reentrant recovery joins this exact operation.
    _publish(session, KeyRecordingStatus.pending);
    return op;
  }

  /// A fresh key hold supersedes older permission/start/delivery publication.
  Future<void> start() {
    if (_disposed || !_allowed()) return Future<void>.value();
    final session = ++_session;
    _ended = false;
    _publish(session, KeyRecordingStatus.pending);
    return _enqueue(session, () async {
      // Previous owned resource must resolve before a fresh key start.
      await _cleanup();
      if (!_current(session) || _ended) return;
      final permission = await _capture.hasPermission();
      if (!_current(session) || _ended) return;
      if (!permission) {
        _publish(session, KeyRecordingStatus.denied);
        return;
      }
      // Retain ownership even if start fails partially.
      final identity = _capture.acquire();
      if (identity == null) throw const KeyRecordingException();
      _acquisition = identity;
      try {
        await identity.started;
      } catch (_) {
        _captureUncertain = true;
        rethrow;
      }
      if (!_current(session)) {
        await _cleanup();
        return;
      }
      if (!_ended) _publish(session, KeyRecordingStatus.listening);
    });
  }

  /// Releases the current key intent. Pre-start release never starts later.
  Future<void> send() {
    if (_disposed || _ended) return Future<void>.value();
    final session = _session;
    _ended = true;
    return _enqueue(session, () async {
      final file = await _stopOwned();
      if (!_current(session)) {
        await _deletePending();
        return;
      }
      if (file == null) {
        if (_status != KeyRecordingStatus.denied) {
          _publish(session, KeyRecordingStatus.empty);
        }
        return;
      }
      // Transfer exactly once on entry to the existing utterance processor.
      _pendingFile = null;
      _acquisition = null;
      await _deliver(file);
    });
  }

  /// Cancel/reset invalidates pending start/send before ordered owned cleanup.
  Future<void> cancel() {
    final session = ++_session;
    _ended = true;
    return _enqueue(session, () async {
      await _cleanup();
      _publish(session, KeyRecordingStatus.idle);
    });
  }

  /// Whether close encountered cleanup or capture disposal uncertainty.
  bool get closeFailed => _closeFailed;

  /// Shared close path: always attempts capture disposal exactly once, even
  /// when intent cleanup fails. Disposal is not verified stop or file erasure.
  Future<void> closeCapture() => _close ??= _finishClose();

  Future<void> _finishClose() async {
    try {
      await disposeIntent();
    } catch (_) {
      _closeFailed = true;
    }
    try {
      await _capture.dispose();
    } catch (_) {
      _closeFailed = true;
    }
  }

  /// Attempts owned cleanup before caller closes the shared capture.
  /// Repeated dispose can retry separately key-owned file deletion only.
  /// Capture cleanup uncertainty stays retained; disposed owners cannot
  /// recover or revive. [closeCapture] still attempts shared disposal.
  Future<void> disposeIntent() {
    _disposed = true;
    _ended = true;
    final session = ++_session;
    return _enqueue(session, () => _cleanup());
  }
}
