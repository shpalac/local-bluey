import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_bluey/services/biometric_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth implements Authenticator {
  _FakeAuth(this.result);
  AuthResult result;
  @override
  Future<AuthResult> authenticate({required String reason}) async => result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('#92: lock off passes through without authenticating', () async {
    final fake = _FakeAuth(AuthResult.failed);
    BiometricLock.instance.debugAuthenticator = fake;
    await BiometricLock.instance.setEnabled(false);
    expect(
      await BiometricLock.instance.requireAuth(reason: 'open'),
      AuthResult.success,
    );
  });

  test('#92: lock on defers to the authenticator', () async {
    final fake = _FakeAuth(AuthResult.success);
    BiometricLock.instance.debugAuthenticator = fake;
    await BiometricLock.instance.setEnabled(true);
    expect(
      await BiometricLock.instance.requireAuth(reason: 'open'),
      AuthResult.success,
    );
    fake.result = AuthResult.failed;
    expect(
      await BiometricLock.instance.requireAuth(reason: 'open'),
      AuthResult.failed,
    );
    fake.result = AuthResult.unavailable;
    expect(
      await BiometricLock.instance.requireAuth(reason: 'open'),
      AuthResult.unavailable,
    );
    await BiometricLock.instance.setEnabled(false);
  });

  test('#92: enabled flag persists and defaults to off', () async {
    SharedPreferences.setMockInitialValues({});
    await BiometricLock.instance.load();
    expect(BiometricLock.instance.enabled, isFalse);
    SharedPreferences.setMockInitialValues({'lock.enabled': true});
    await BiometricLock.instance.load();
    expect(BiometricLock.instance.enabled, isTrue);
    await BiometricLock.instance.setEnabled(false);
  });
  for (final result in [
    AuthResult.failed,
    AuthResult.unavailable,
    AuthResult.error,
  ]) {
    test('enable ${result.name} never persists an enabled lock', () async {
      final lock = BiometricLock.forTesting(authenticator: _FakeAuth(result));
      expect(await lock.setEnabled(true), result);
      expect(lock.enabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool('lock.enabled'),
        isNot(true),
      );
    });
  }

  test(
    'platform exceptions distinguish missing credentials from errors',
    () async {
      final auth = _PlatformAuth();
      final adapter = LocalAuthAuthenticator(auth: auth);
      for (final code in ['PasscodeNotSet', 'NotEnrolled', 'NotAvailable']) {
        auth.code = code;
        expect(
          await adapter.authenticate(reason: 'fixture'),
          AuthResult.unavailable,
        );
      }
      auth.code = 'OtherTransientError';
      expect(await adapter.authenticate(reason: 'fixture'), AuthResult.error);
    },
  );
}

class _PlatformAuth extends LocalAuthentication {
  String code = 'PasscodeNotSet';

  @override
  Future<bool> isDeviceSupported() async => throw PlatformException(code: code);
}
