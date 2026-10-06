import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Outcome of one authentication attempt.
enum AuthResult { success, failed, unavailable }

/// Injectable authenticator so tests drive success, failure, and
/// unavailable cases (#92).
abstract class Authenticator {
  /// Prompts the user to authenticate; [reason] is shown by the OS.
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

  /// The shared lock.
  static final BiometricLock instance = BiometricLock._();

  static const _kEnabled = 'lock.enabled';

  Authenticator _authenticator = LocalAuthAuthenticator();
  bool _enabled = false;

  /// Whether the app lock is on (persisted).
  bool get enabled => _enabled;

  @visibleForTesting
  /// Test seam: replaces the authenticator.
  set debugAuthenticator(Authenticator a) => _authenticator = a;

  /// Loads the persisted enabled flag.
  Future<void> load() async {
    _enabled =
        (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;
  }

  /// Toggles the lock and persists the choice.
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
