import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Outcome of one authentication attempt.
enum AuthResult { success, failed, unavailable, error }

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
    } on PlatformException catch (error) {
      // Missing device credentials require setup, not an app-lock bypass.
      if (error.code == 'PasscodeNotSet' ||
          error.code == 'NotEnrolled' ||
          error.code == 'NotAvailable') {
        return AuthResult.unavailable;
      }
      return AuthResult.error;
    } catch (_) {
      return AuthResult.error;
    }
  }
}

/// Optional app lock (#92): off by default; when on, gated screens (phone
/// remote, Settings with API key + safety) require Face ID/Touch ID or the
/// device passcode.
class BiometricLock {
  BiometricLock._();

  /// Isolated lock for injected authentication and widget fixtures.
  @visibleForTesting
  BiometricLock.forTesting({
    required Authenticator authenticator,
    bool enabled = false,
  }) : _authenticator = authenticator,
       _enabled = enabled;

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

  /// Enabling first proves authentication works, then persists the choice.
  /// Failure never enables the lock. Disabling is available only in gated UI.
  Future<AuthResult> setEnabled(
    bool value, {
    String reason = 'Enable Bluey app lock',
  }) async {
    if (value && !_enabled) {
      final result = await _authenticate(reason);
      if (result != AuthResult.success) return result;
    }
    try {
      final saved = await (await SharedPreferences.getInstance()).setBool(
        _kEnabled,
        value,
      );
      if (!saved) return AuthResult.error;
      _enabled = value;
      return AuthResult.success;
    } catch (_) {
      return AuthResult.error;
    }
  }

  Future<AuthResult> _authenticate(String reason) async {
    try {
      return await _authenticator.authenticate(reason: reason);
    } catch (_) {
      return AuthResult.error;
    }
  }

  /// True when the gate may open. Passes straight through when the lock is
  /// off; otherwise asks the device for biometrics/passcode (#92).
  Future<AuthResult> requireAuth({required String reason}) async {
    if (!_enabled) return AuthResult.success;
    return _authenticate(reason);
  }
}
