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
class BiometricLock extends ChangeNotifier {
  BiometricLock._() : _write = null, _remove = null;

  /// Isolated lock for injected authentication and widget fixtures.
  @visibleForTesting
  factory BiometricLock.forTesting({
    required Authenticator authenticator,
    bool enabled = false,
    Future<bool> Function(bool value)? write,
    Future<bool> Function()? remove,
  }) => BiometricLock._fixture(authenticator, enabled, write, remove);

  BiometricLock._fixture(
    this._authenticator,
    this._enabled,
    this._write,
    this._remove,
  );

  /// The shared lock.
  static final BiometricLock instance = BiometricLock._();

  static const _kEnabled = 'lock.enabled';

  Authenticator _authenticator = LocalAuthAuthenticator();
  bool _enabled = false;
  final Future<bool> Function(bool value)? _write;
  final Future<bool> Function()? _remove;

  /// Bumped by every explicit clear so older entered work cannot undo it.
  int _generation = 0;

  /// Tail of the preference write queue; writes and removal run in order.
  Future<void> _tail = Future<void>.value();

  Future<T> _queued<T>(Future<T> Function() op) {
    final done = _tail.then((_) => op());
    _tail = done.then<void>((_) {}, onError: (_) {});
    return done;
  }

  Future<bool> _persist(bool value) async => _write != null
      ? _write(value)
      : (await SharedPreferences.getInstance()).setBool(_kEnabled, value);

  Future<bool> _removeStored() async => _remove != null
      ? _remove()
      : (await SharedPreferences.getInstance()).remove(_kEnabled);

  /// Whether the app lock is on (persisted).
  bool get enabled => _enabled;

  @visibleForTesting
  /// Test seam: replaces the authenticator.
  set debugAuthenticator(Authenticator a) => _authenticator = a;

  /// Loads the persisted enabled flag.
  Future<void> load() => _queued(() async {
    final value =
        (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
  });

  /// Explicit preference deletion (data registry): invalidates entered enable
  /// or write work, removes the stored value in order after any write already
  /// entered, then publishes the default-off state. Throws when removal fails
  /// so the caller can report it; the cached state then still matches storage.
  Future<void> clearPreference() {
    _generation++;
    return _queued(() async {
      final removed = await _removeStored();
      if (!removed) {
        throw StateError('Could not remove the app-lock preference');
      }
      if (_enabled) {
        _enabled = false;
        notifyListeners();
      }
    });
  }

  /// Enabling first proves authentication works, then persists the choice.
  /// Failure never enables the lock. Disabling is available only in gated UI.
  Future<AuthResult> setEnabled(
    bool value, {
    String reason = 'Enable Bluey app lock',
  }) async {
    final generation = _generation;
    if (value && !_enabled) {
      final result = await _authenticate(reason);
      if (result != AuthResult.success) return result;
    }
    // A clear that ran while authentication was pending wins.
    if (generation != _generation) {
      return value ? AuthResult.failed : AuthResult.success;
    }
    try {
      return await _queued(() async {
        if (generation != _generation) {
          return value ? AuthResult.failed : AuthResult.success;
        }
        if (!await _persist(value)) return AuthResult.error;
        if (_enabled != value) {
          _enabled = value;
          notifyListeners();
        }
        return AuthResult.success;
      });
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
