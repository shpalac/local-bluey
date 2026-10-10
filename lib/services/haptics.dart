import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tactile feedback for the phone remote (#88). One injectable interface so
/// tests can count exactly one haptic per event.
abstract class Haptics {
  /// Subtle tap (success, acknowledgment).
  Future<void> light();

  /// Noticeable tap (wake, mode change).
  Future<void> medium();

  /// Heavy tap for failures.
  Future<void> error();
}

/// Device haptics via Flutter's HapticFeedback.
class SystemHaptics implements Haptics {
  const SystemHaptics();

  @override
  Future<void> light() => HapticFeedback.lightImpact();
  @override
  Future<void> medium() => HapticFeedback.mediumImpact();
  @override
  Future<void> error() => HapticFeedback.heavyImpact();
}

/// No-op haptics (disabled, or unsupported platform).
class NullHaptics implements Haptics {
  const NullHaptics();

  @override
  Future<void> light() async {}
  @override
  Future<void> medium() async {}
  @override
  Future<void> error() async {}
}

/// Events the remote confirms with touch (#88).
enum RemoteHapticEvent { holdStart, ack, answer, error, connect, disconnect }

/// Safe preference storage failure, without raw plugin details.
class HapticsStorageException implements Exception {
  /// Creates a generic failure.
  const HapticsStorageException();

  @override
  String toString() => 'Haptics preference could not be updated.';
}

/// Fires one haptic per remote event, behind a Settings toggle.
class RemoteHaptics extends ChangeNotifier {
  RemoteHaptics._({
    Future<bool?> Function()? read,
    Future<bool> Function(bool)? write,
    Future<bool> Function()? remove,
  }) : _read =
           read ??
           (() async =>
               (await SharedPreferences.getInstance()).getBool(_kEnabled)),
       _write =
           write ??
           ((value) async => (await SharedPreferences.getInstance()).setBool(
             _kEnabled,
             value,
           )),
       _remove =
           remove ??
           (() async =>
               (await SharedPreferences.getInstance()).remove(_kEnabled));

  /// Isolated entered preference operations for tests.
  @visibleForTesting
  RemoteHaptics.forTest({
    required Future<bool?> Function() read,
    required Future<bool> Function(bool) write,
    required Future<bool> Function() remove,
  }) : this._(read: read, write: write, remove: remove);

  /// Shared dispatcher.
  static final RemoteHaptics instance = RemoteHaptics._();

  /// Widget fixture override, restored after each test.
  @visibleForTesting
  static RemoteHaptics? debugOverride;

  /// Service used by the registry and Settings tile.
  static RemoteHaptics get current => debugOverride ?? instance;

  static const _kEnabled = 'haptics.enabled';
  final Future<bool?> Function() _read;
  final Future<bool> Function(bool) _write;
  final Future<bool> Function() _remove;
  Future<void> _io = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  Haptics _impl = const SystemHaptics();
  bool _enabled = true;

  /// Last loaded or successfully persisted state.
  bool get enabled => _enabled;

  /// Replaces physical feedback for counting fixtures.
  @visibleForTesting
  set debugImpl(Haptics impl) => _impl = impl;

  void _publish(bool value, int generation) {
    if (_disposed || generation != _generation) return;
    _enabled = value;
    notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function(int) action) {
    final generation = ++_generation;
    final next = _io.then((_) async {
      try {
        await action(generation);
      } catch (_) {
        if (!_disposed && generation == _generation) {
          try {
            _publish(await _read() ?? true, generation);
          } catch (_) {}
        }
        throw const HapticsStorageException();
      }
    });
    _io = next.catchError((_) {});
    return next;
  }

  /// Ordered load, with superseded publication rejected.
  Future<void> load() => _enqueue((generation) async {
    _publish(await _read() ?? true, generation);
  });

  /// Persists before publishing, with safe failure/retry.
  Future<void> setEnabled(bool value) => _enqueue((generation) async {
    if (generation != _generation) return;
    if (!await _write(value)) throw const HapticsStorageException();
    _publish(value, generation);
  });

  /// Explicit registry deletion resets existing default-on after success.
  Future<void> clear() => _enqueue((generation) async {
    if (!await _remove()) throw const HapticsStorageException();
    _publish(true, generation);
  });

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  /// Exactly one haptic per event; none when the toggle is off (#88).
  Future<void> fire(RemoteHapticEvent event) async {
    if (!_enabled) return;
    switch (event) {
      case RemoteHapticEvent.holdStart:
        await _impl.medium();
      case RemoteHapticEvent.ack:
      case RemoteHapticEvent.answer:
      case RemoteHapticEvent.connect:
        await _impl.light();
      case RemoteHapticEvent.error:
        await _impl.error();
      case RemoteHapticEvent.disconnect:
        await _impl.medium();
    }
  }
}
