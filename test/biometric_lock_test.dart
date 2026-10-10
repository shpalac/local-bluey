import 'dart:async';

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

  group('#363 explicit preference clear', () {
    test('clear removes storage and cached state and notifies', () async {
      SharedPreferences.setMockInitialValues({'lock.enabled': true});
      final lock = BiometricLock.forTesting(
        authenticator: _FakeAuth(AuthResult.success),
      );
      await lock.load();
      expect(lock.enabled, isTrue);
      var notified = 0;
      lock.addListener(() => notified++);
      await lock.clearPreference();
      expect(lock.enabled, isFalse);
      expect(notified, 1);
      expect(
        (await SharedPreferences.getInstance()).containsKey('lock.enabled'),
        isFalse,
      );
    });

    test(
      'an enable authentication entered before clear is discarded',
      () async {
        final auth = _HeldAuth();
        final lock = BiometricLock.forTesting(authenticator: auth);
        final pending = lock.setEnabled(true);
        await Future<void>.delayed(Duration.zero);
        expect(auth.entered, isTrue);
        await lock.clearPreference();
        auth.release.complete(AuthResult.success);
        expect(await pending, isNot(AuthResult.success));
        expect(lock.enabled, isFalse);
        expect(
          (await SharedPreferences.getInstance()).containsKey('lock.enabled'),
          isFalse,
        );
        // A fresh enable needs fresh authentication and works.
        final fresh = _HeldAuth();
        final lock2 = BiometricLock.forTesting(authenticator: fresh);
        final again = lock2.setEnabled(true);
        await Future<void>.delayed(Duration.zero);
        expect(lock2.enabled, isFalse);
        fresh.release.complete(AuthResult.success);
        expect(await again, AuthResult.success);
        expect(lock2.enabled, isTrue);
      },
    );

    test('clear is ordered after a write already entered', () async {
      final write = Completer<bool>();
      var removed = false;
      final order = <String>[];
      final lock = BiometricLock.forTesting(
        authenticator: _FakeAuth(AuthResult.success),
        write: (v) {
          order.add('write');
          return write.future;
        },
        remove: () async {
          order.add('remove');
          removed = true;
          return true;
        },
      );
      final enable = lock.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      final clear = lock.clearPreference();
      await Future<void>.delayed(Duration.zero);
      expect(removed, isFalse, reason: 'removal waits for the entered write');
      write.complete(true);
      await enable;
      await clear;
      expect(order, ['write', 'remove']);
      expect(lock.enabled, isFalse);
    });

    test('a write queued after clear is dropped', () async {
      final write = Completer<bool>();
      final lock = BiometricLock.forTesting(
        authenticator: _FakeAuth(AuthResult.success),
        enabled: true,
        write: (v) => write.future,
      );
      final first = lock.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      final disable = lock.setEnabled(false);
      await Future<void>.delayed(Duration.zero);
      final clear = lock.clearPreference();
      write.complete(true);
      await first;
      expect(await disable, AuthResult.success);
      await clear;
      expect(lock.enabled, isFalse);
    });

    test('removal failure reaches the caller and retry works', () async {
      var fail = true;
      final lock = BiometricLock.forTesting(
        authenticator: _FakeAuth(AuthResult.success),
        enabled: true,
        remove: () async {
          if (fail) throw StateError('secret path /private/prefs.plist');
          return true;
        },
      );
      await expectLater(
        lock.clearPreference(),
        throwsA(
          isA<AppLockClearException>().having(
            (e) => e.toString(),
            'message',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(lock.enabled, isTrue, reason: 'cache still matches storage');
      fail = false;
      await lock.clearPreference(); // queue still usable
      expect(lock.enabled, isFalse);
    });

    test('failed authentication does not disable an enabled lock', () async {
      final lock = BiometricLock.forTesting(
        authenticator: _FakeAuth(AuthResult.failed),
        enabled: true,
      );
      expect(await lock.requireAuth(reason: 'x'), AuthResult.failed);
      expect(lock.enabled, isTrue);
    });
  });
}

class _HeldAuth implements Authenticator {
  final release = Completer<AuthResult>();
  bool entered = false;
  @override
  Future<AuthResult> authenticate({required String reason}) {
    entered = true;
    return release.future;
  }
}

class _PlatformAuth extends LocalAuthentication {
  String code = 'PasscodeNotSet';

  @override
  Future<bool> isDeviceSupported() async => throw PlatformException(code: code);
}
