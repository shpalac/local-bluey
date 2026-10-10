import 'package:flutter/foundation.dart';

import '../llm/brain.dart';
import 'privacy_guard.dart';
import 'settings_store.dart';

// Stage all values before any listener sees the coherent snapshot.
class _StagedNotifier<T> extends ValueNotifier<T> {
  _StagedNotifier(this._current) : super(_current);
  T _current;
  @override
  T get value => _current;
  @override
  set value(T next) {
    if (stage(next)) notifyListeners();
  }

  bool stage(T next) {
    if (_current == next) return false;
    _current = next;
    return true;
  }

  void publish() => notifyListeners();
}

/// Isolated reload owner, with narrow offline fixture dependencies. Current
/// errors propagate retaining the prior coherent state; stale errors/results
/// are discarded. A constructed brain is not network/model readiness proof.
class BrainHostState {
  /// Defaults retain the production settings/privacy/provider path.
  BrainHostState({
    Future<BrainSettings> Function()? load,
    Future<String?> Function(BrainSettings)? refusal,
    Brain Function(BrainSettings)? build,
  }) : _load = load ?? SettingsStore.load,
       _refusal = refusal ?? PrivacyGuard.refusal,
       _build = build ?? ((settings) => settings.buildBrain());
  final Future<BrainSettings> Function() _load;
  final Future<String?> Function(BrainSettings) _refusal;
  final Brain Function(BrainSettings) _build;
  final _brain = _StagedNotifier<Brain?>(null);
  final _refused = _StagedNotifier<String?>(null);
  final _remote = _StagedNotifier<bool>(false);
  int _generation = 0;

  /// Current provider, or null while uninitialized/refused.
  ValueNotifier<Brain?> get brain => _brain;

  /// Current privacy refusal, not an endpoint readiness result.
  ValueNotifier<String?> get refusedReason => _refused;

  /// Whether the current provider URL is off-device.
  ValueNotifier<bool> get remoteActive => _remote;

  /// Latest invocation owns publication across settings/refusal waits. Builds
  /// before staging; all three values change before the first notification.
  /// Reentrant reload takes ownership; old remaining notifications stop.
  Future<void> reload() async {
    final gen = ++_generation;
    bool stale() => gen != _generation;
    try {
      final settings = await _load();
      if (stale()) return;
      final reason = await _refusal(settings);
      if (stale()) return;
      final next = reason == null ? _build(settings) : null;
      final remote =
          reason == null && !PrivacyGuard.isLocalUrl(settings.baseUrl);
      if (stale()) return;
      final brainChanged = _brain.stage(next);
      final refusedChanged = _refused.stage(reason);
      final remoteChanged = _remote.stage(remote);
      if (brainChanged) _brain.publish();
      if (stale()) return;
      if (refusedChanged) _refused.publish();
      if (stale()) return;
      if (remoteChanged) _remote.publish();
    } catch (_) {
      if (stale()) return;
      rethrow;
    }
  }
}

/// Holds the live brain rebuilt when settings change. Static notifier API
/// remains compatible; publication is owned by the isolated production state.
class BrainHost {
  BrainHost._();
  static final _state = BrainHostState();

  /// Active brain; null until first reload or while refused.
  static final ValueNotifier<Brain?> brain = _state.brain;

  /// Current local-only refusal shown by the UI.
  static final ValueNotifier<String?> refusedReason = _state.refusedReason;

  /// True when the current provider talks off-device.
  static final ValueNotifier<bool> remoteActive = _state.remoteActive;

  /// Loads settings and rebuilds; latest invocation wins, errors retain prior
  /// coherent state. Construction is not a provider readiness check.
  static Future<void> reload() => _state.reload();
}
