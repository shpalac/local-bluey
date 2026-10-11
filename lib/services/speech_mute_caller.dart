import 'dart:async';

import 'package:flutter/foundation.dart';

import 'speech.dart';

/// Local stop observation, never remote receipt or file-erasure proof.
class SpeechMuteCaller extends ChangeNotifier {
  SpeechMuteCaller({
    required SpeechService owner,
    required void Function() broadcast,
  }) : this.operations(owner.stop, broadcast);
  SpeechMuteCaller.operations(this._stop, this._broadcast);
  final Future<void> Function() _stop;
  final void Function() _broadcast;
  Future<void>? _pending;
  bool _failed = false, _disposed = false, _notifierDisposed = false;
  int _notifyDepth = 0;
  bool get loading => _pending != null;
  bool get failed => _failed;
  bool get visible => loading || failed;

  /// Every explicit mute event broadcasts immediately, including duplicates.
  /// Local duplicates join the entered owner stop instead of issuing another.
  Future<void> mute() {
    if (_disposed) return Future<void>.value();
    final pending = _pending;
    if (pending != null) {
      _broadcast();
      return pending;
    }
    final done = Completer<void>();
    _pending = done.future;
    _failed = false;
    Future<void> work;
    try {
      work = _stop(); // Owner generation invalidation is immediate.
    } catch (_) {
      work = Future<void>.error(StateError('Local stop failed'));
    }
    // Attach consumption before any external callback or notification.
    work.then<void>(
      (_) => _settle(done, false),
      onError: (Object _, StackTrace _) => _settle(done, true),
    );
    _broadcast();
    if (!_disposed) _publish();
    return done.future;
  }

  void _settle(Completer<void> done, bool failed) {
    _pending = null;
    if (!_disposed) {
      _failed = failed;
      _publish();
    }
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
    if (_notifyDepth == 0 && !_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}
