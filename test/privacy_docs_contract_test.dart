import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/privacy_guard.dart';

/// Source-backed contract for the privacy wording (#290). Every example is
/// synthetic. The table says what the scrubber does and does not do; the
/// docs may claim no more than this.
void main() {
  // (label, text, scrubbed?)
  const table = <(String, String, bool)>[
    ('email address', 'write to ana@example.test now', true),
    ('16-digit card shape', 'card 4000 0000 0000 0002 ok', true),
    ('9-digit number', 'ref 123456789 end', true),
    ('ordinary text', 'Meeting moved to Tuesday at 10', false),
    ('password-shaped text', 'password: Tr0ub4dor&3', false),
    ('token-shaped text', 'api token: example-not-real', false),
  ];

  for (final (label, text, scrubbed) in table) {
    test('scrubber: $label ${scrubbed ? 'is' : 'is not'} replaced', () {
      expect(PrivacyGuard.hasSensitive(text), scrubbed);
      expect(PrivacyGuard.redact(text).contains('[redacted]'), scrubbed);
      if (!scrubbed) expect(PrivacyGuard.redact(text), text);
    });
  }

  group('docs stay within that contract', () {
    final guide = File('docs/USER_GUIDE.md').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    test('user guide does not claim passwords/tokens are redacted', () {
      final lower = guide.toLowerCase();
      expect(lower, isNot(contains('redacts sensitive text')));
      expect(lower, contains('passwords and tokens are'));
      expect(lower, contains('not recognised'));
    });

    test('user guide says the toggle does not edit screenshots', () {
      expect(guide, contains('does not edit screenshots'));
      expect(guide, contains('images are never edited'));
    });

    test('user guide and README state the pattern limits', () {
      expect(guide, contains('can miss secrets'));
      expect(readme, contains('not a guarantee'));
      expect(readme, contains('can still miss secrets'));
    });

    test('README lists the same pattern families as the scrubber', () {
      expect(readme, contains('email addresses, 16-digit card numbers'));
      expect(readme, contains('9-digit numbers'));
    });
  });
}
