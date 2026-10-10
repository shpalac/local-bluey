import 'package:flutter/foundation.dart';

import 'brain_host.dart';

/// Contains caller errors without changing the host's retained snapshot policy.
class HostReloadController extends ChangeNotifier {
  /// Production reload by default; injected entered operations for fixtures.
  HostReloadController({Future<void> Function()? reload})
    : _reload = reload ?? BrainHost.reload;
  final Future<void> Function() _reload;
  int _generation = 0;
  bool _disposed = false;
  bool _failed = false;
  bool _loading = false;
  bool _notifying = false, _notifierDisposed = false;
  Future<void>? _pending;

  /// A current caller failed. No raw error or provider readiness claim.
  bool get failed => _failed;

  /// A caller is currently awaiting its reload.
  bool get loading => _loading;

  /// Every startup/settings/delete-all invocation takes latest ownership.
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

  /// Explicit retries coalesce while the current caller is entered.
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
