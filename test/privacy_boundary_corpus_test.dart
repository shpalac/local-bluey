import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/watch_policy.dart';

void main() {
  for (final secret in [
    'sample@fixture.invalid',
    '4111-1111-1111-1111',
    '123456789',
  ]) {
    test('fabricated delimiter corpus redacts $secret', () {
      for (final delimiter in [' ', '\n', '\t', ':', '(', 'שלום']) {
        final text = '$delimiter$secret$delimiter';
        expect(PrivacyGuard.hasSensitive(text), isTrue);
        final result = PrivacyGuard.redact(text);
        expect(result, isNot(contains(secret)));
        expect(PrivacyGuard.redact(result), result);
      }
    });
  }
  test('unicode obfuscation remains an explicit supplemental-regex gap', () {
    for (final text in [
      'sample＠fixture.invalid',
      '１２３４５６７８９',
      '4111\u200b1111\u200b1111\u200b1111',
    ]) {
      expect(PrivacyGuard.hasSensitive(text), isFalse);
      expect(PrivacyGuard.redact(text), text);
    }
    // These false results cannot grant capture, persistence or model access.
  });
  test(
    'excluded-surface precedence is independent of allowlist membership',
    () async {
      for (final allowed in [
        <String>[],
        ['Safari'],
        [' SAFARI.APP '],
      ]) {
        for (final title in ['בנק דוגמה', 'Bitwarden Vault', 'חלון פרטי']) {
          expect(
            await WatchPolicy.verdict(
              frontApp: 'Safari',
              windowTitle: title,
              locked: true,
              allowedApps: allowed,
              deniedApps: [],
            ),
            WatchVerdict.locked,
          );
          expect(
            await WatchPolicy.verdict(
              frontApp: 'Safari',
              windowTitle: title,
              allowedApps: allowed,
              deniedApps: [],
            ),
            isNot(WatchVerdict.allow),
          );
        }
      }
    },
  );
}
