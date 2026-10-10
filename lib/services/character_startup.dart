import 'package:flutter/foundation.dart';

import 'characters.dart';

/// Contains character-load failures without changing the character owner's retained choice policy.
class CharacterStartup extends ChangeNotifier {
  CharacterStartup({Future<void> Function()? reload, bool Function()? verified})
    : _reload = reload ?? CharacterStore.instance.load,
      _verified = verified ?? (() => CharacterStore.instance.verified);
  final Future<void> Function() _reload;
  final bool Function() _verified;
  bool get verified => _verified();
  int _generation = 0;
  bool _disposed = false, _failed = false, _loading = false;
  bool _notifying = false, _notifierDisposed = false;
  Future<void>? _pending;
  bool get failed => _failed;
  bool get loading => _loading;

  void _publish() {
    _notifying = true;
    try {
      notifyListeners();
    } finally {
      _notifying = false;
      if (_disposed && !_notifierDisposed) {
        _notifierDisposed = true;
        super.dispose();
      }
    }
  }

  /// Every character load takes latest publication ownership.
  Future<void> reload() {
    if (_disposed) return Future<void>.value();
    final generation = ++_generation;
    final op = Future<void>.microtask(() => _run(generation));
    _pending = op;
    op.then((_) {
      if (identical(_pending, op)) _pending = null;
    });
    return op;
  }

  Future<void> _run(int generation) async {
    if (_disposed || generation != _generation) return;
    _loading = true;
    _publish();
    if (_disposed || generation != _generation) return;
    var failed = false;
    try {
      await _reload();
    } catch (_) {
      failed = true;
    }
    if (_disposed || generation != _generation) return;
    _failed = failed;
    _loading = false;
    _publish();
  }

  /// Explicit retries join current entered load; no automatic retry loop.
  Future<void> retry() {
    if (_disposed) return Future<void>.value();
    return _pending ?? reload();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    if (!_notifying && !_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}
