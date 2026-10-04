import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AuthResult { success, failed, unavailable }

/// Injectable authenticator so tests drive success, failure, and
/// unavailable cases (#92).
abstract class Authenticator {
  Future<AuthResult> authenticate({required String reason});
}

/// Device biometrics with passcode fallback (biometricOnly: false).
class LocalAuthAuthenticator implements Authenticator {
  LocalAuthAuthenticator({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<AuthResult> authenticate({required String reason}) async {
    try {
      final supported =
          await _auth.isDeviceSupported() || await _auth.canCheckBiometrics;
      if (!supported) return AuthResult.unavailable;
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: false),
      );
      return ok ? AuthResult.success : AuthResult.failed;
    } catch (_) {
      return AuthResult.unavailable;
    }
  }
}

/// Optional app lock (#92): off by default; when on, gated screens (phone
/// remote, Settings with API key + safety) require Face ID/Touch ID or the
/// device passcode.
class BiometricLock {
  BiometricLock._();
  static final BiometricLock instance = BiometricLock._();

  static const _kEnabled = 'lock.enabled';

  Authenticator _authenticator = LocalAuthAuthenticator();
  bool _enabled = false;

  bool get enabled => _enabled;

  @visibleForTesting
  set debugAuthenticator(Authenticator a) => _authenticator = a;

  Future<void> load() async {
    _enabled =
        (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await (await SharedPreferences.getInstance()).setBool(_kEnabled, value);
  }

  /// True when the gate may open. Passes straight through when the lock is
  /// off; otherwise asks the device for biometrics/passcode (#92).
  Future<AuthResult> requireAuth({required String reason}) async {
    if (!_enabled) return AuthResult.success;
    return _authenticator.authenticate(reason: reason);
  }
}
