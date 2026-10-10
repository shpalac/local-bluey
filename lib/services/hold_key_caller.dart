// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import 'hold_key_controller.dart';

/// Observes host lifecycle calls without changing retained preference or bridge policy.
class HoldKeyCaller extends ChangeNotifier {
  HoldKeyCaller({
    required HoldKeySettings settings,
    required HoldKeyController controller,
  }) : this.operations(
         load: settings.load,
         sync: controller.sync,
         close: controller.dispose,
       );

  /// Same invocation/observation owner with injected entered operations.
  // Public operation names keep this seam explicit at fixture call sites.
  HoldKeyCaller.operations({
    required Future<void> Function() load,
    required Future<void> Function() sync,
    required Future<void> Function() close,
  }) : _load = load,
       _sync = sync,
       _close = close;
  final Future<void> Function() _load, _sync, _close;
  bool _disposed = false, _failed = false, _loading = false;
  bool _closeFailed = false;
  bool _reading = false;
  int _revision = 0;
  Future<void>? _loadOp, _closeOp;

  /// Current call failure only, not shortcut readiness or stopped state.
  bool get failed => _failed;
  bool get loading => _loading;

  /// Retained close observation, with no post-disposal UI publication.
  bool get closeFailed => _closeFailed;

  Future<void> _observe(Future<void> Function() action) async {
    if (_disposed) return;
    final revision = ++_revision;
    _loading = true;
    notifyListeners();
    if (_disposed || revision != _revision) return;
    var failed = false;
    try {
      await action();
    } catch (_) {
      failed = true;
    }
    if (_disposed || revision != _revision) return;
    _failed = failed;
    _loading = false;
    notifyListeners();
  }

  /// Settings listeners during owned load are covered by its following sync.
  Future<void> sync() {
    if (_disposed) return Future<void>.value();
    if (_reading && _loadOp != null) return _loadOp!;
    return _observe(_sync);
  }

  /// Startup and explicit retry must freshly load before requesting sync.
  Future<void> loadAndSync() {
    if (_disposed) return Future<void>.value();
    final pending = _loadOp;
    if (pending != null) return pending;
    // Install ownership before load can publish synchronous listener events.
    _reading = true;
    final op = Future<void>.microtask(
      () => _observe(() async {
        try {
          await _load();
        } finally {
          _reading = false;
        }
        if (!_disposed) await _sync();
      }),
    );
    _loadOp = op;
    op.then((_) {
      if (identical(_loadOp, op)) _loadOp = null;
    });
    return op;
  }

  Future<void> retry() => loadAndSync();

  /// Close is contained/coalesced, even after notifier disposal/unmount.
  Future<void> close() {
    if (_closeOp != null) return _closeOp!;
    _disposed = true;
    _revision++;
    final op = Future<void>.microtask(() async {
      try {
        await _close();
        _closeFailed = false;
      } catch (_) {
        _closeFailed = true;
      }
    });
    _closeOp = op;
    op.then((_) {
      if (identical(_closeOp, op)) _closeOp = null;
    });
    return op;
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
