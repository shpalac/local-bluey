import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BLU-035: guards the rollout/rollback documentation contract. The doc must
/// keep rollback guidance and must not claim capabilities that are not
/// implemented on main.
void main() {
  final doc = File('docs/BLU-035-rollout-rollback.md').readAsStringSync();

  test('rollout and rollback guidance is documented', () {
    expect(doc, contains('## Current rollout guidance'));
    expect(doc, contains('## Rollback guidance'));
    expect(doc, contains('Disable the relevant feature flag'));
    expect(doc, contains('Preserve user data'));
  });

  test('doc claims no capabilities that are not implemented', () {
    expect(
      doc,
      contains(
        'does not claim rollout support for features that are not '
        'implemented',
      ),
    );
    expect(doc, contains('## Out of scope'));
    expect(doc, contains('documentation placeholders only'));
  });
}
