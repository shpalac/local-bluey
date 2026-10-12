import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/watch_policy.dart';

void main() {
  for (final value in [
    'sample@fixture.invalid',
    '4111 1111 1111 1111',
    '123456789',
  ]) {
    test(
      'fabricated PII is redacted in Hebrew and redaction is idempotent',
      () {
        final text = 'בדיקת דוגמה לפני $value אחרי';
        expect(PrivacyGuard.hasSensitive(text), isTrue);
        final redacted = PrivacyGuard.redact(text);
        expect(redacted, 'בדיקת דוגמה לפני [redacted] אחרי');
        expect(PrivacyGuard.redact(redacted), redacted);
        expect(PrivacyGuard.hasSensitive(redacted), isFalse);
      },
    );
  }
  test('supplemental regex never establishes arbitrary token safety', () {
    // Honest limit: classification/inference permission must not use this
    // false result as proof that an unknown secret or image is safe.
    const unknown = 'fabricated-token-שלום';
    expect(PrivacyGuard.hasSensitive(unknown), isFalse);
    expect(PrivacyGuard.redact(unknown), unknown);
  });
  for (final title in [
    'בנק דוגמה',
    'חלון פרטי',
    'Bitwarden Vault',
    'Bank fixture',
  ]) {
    test(
      'fabricated denied title stays denied under app normalization',
      () async {
        for (final app in ['Safari', ' SAFARI.APP ', 'safari']) {
          final v = await WatchPolicy.verdict(
            frontApp: app,
            windowTitle: title,
            allowedApps: ['Safari'],
            deniedApps: const [],
          );
          expect(v, isNot(WatchVerdict.allow));
          expect(
            await WatchPolicy.verdict(
              frontApp: app,
              windowTitle: title,
              locked: true,
              allowedApps: ['Safari'],
              deniedApps: const [],
            ),
            WatchVerdict.locked,
          );
        }
      },
    );
  }
  test(
    'added allowlist never defeats user deny or hard secret surface',
    () async {
      for (final app in ['Notes', 'Bitwarden', 'System Settings']) {
        expect(
          await WatchPolicy.verdict(
            frontApp: app,
            allowedApps: [app, 'Safari'],
            deniedApps: [app],
          ),
          WatchVerdict.hardDenied,
        );
      }
    },
  );
  test(
    'local endpoint suffix/userinfo/deceptive host cannot bypass URL guard',
    () {
      for (final url in [
        'https://localhost.fixture.invalid',
        'https://localhost@fixture.invalid',
        'http://127.0.0.1.fixture.invalid',
        'http://[::ffff:192.0.2.1]',
        'http://fixture.local',
        'file://localhost/path',
      ]) {
        expect(PrivacyGuard.isLocalUrl(url), isFalse, reason: url);
      }
      // Loopback proves destination classification only, not server execution
      // isolation, redirection behavior or a model's cloud configuration.
      expect(PrivacyGuard.isLocalUrl('http://127.2.3.4:11434'), isTrue);
    },
  );
}
