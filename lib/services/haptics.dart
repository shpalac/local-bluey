import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tactile feedback for the phone remote (#88). One injectable interface so
/// tests can count exactly one haptic per event.
abstract class Haptics {
  Future<void> light();
  Future<void> medium();
  Future<void> error();
}

class SystemHaptics implements Haptics {
  const SystemHaptics();

  @override
  Future<void> light() => HapticFeedback.lightImpact();
  @override
  Future<void> medium() => HapticFeedback.mediumImpact();
  @override
  Future<void> error() => HapticFeedback.heavyImpact();
}

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

/// Fires one haptic per remote event, behind a Settings toggle.
class RemoteHaptics {
  RemoteHaptics._();
  static final RemoteHaptics instance = RemoteHaptics._();

  static const _kEnabled = 'haptics.enabled';

  Haptics _impl = const SystemHaptics();
  bool _enabled = true;

  bool get enabled => _enabled;

  @visibleForTesting
  set debugImpl(Haptics impl) => _impl = impl;

  Future<void> load() async {
    _enabled =
        (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await (await SharedPreferences.getInstance()).setBool(_kEnabled, value);
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
