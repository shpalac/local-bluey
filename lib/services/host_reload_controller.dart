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

  /// A current caller failed. No raw error or provider readiness claim.
  bool get failed => _failed;

  /// A caller is currently awaiting its reload.
  bool get loading => _loading;

  /// Every startup/settings/delete-all invocation takes latest ownership.
  Future<void> reload() async {
    if (_disposed) return;
    final generation = ++_generation;
    _loading = true;
    notifyListeners();
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
    notifyListeners();
  }

  /// Explicit retries coalesce while the current caller is entered.
  Future<void> retry() async {
    if (_disposed || _loading) return;
    await reload();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
