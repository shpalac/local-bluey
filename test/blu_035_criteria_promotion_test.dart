import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BLU-035 criterion-specific contracts (Refs #591). The rollout/rollback
/// documentation-only gate keeps uniquely-owned, reversible evidence per
/// numbered criterion while no runtime feature exists on main.
void main() {
  final doc = File('docs/BLU-035-rollout-rollback.md').readAsStringSync();

  test('ac2 success and failure fields are documented as non-applicable', () {
    expect(doc, contains('## Out of scope'));
    expect(doc, isNot(contains('Success cases')));
    expect(doc, isNot(contains('Offline')));
    expect(doc, isNot(contains('Timeout')));
  });

  test('ac3 no runtime egress or unsafe surface is promised', () {
    expect(doc, contains('documentation placeholders only'));
    expect(doc, isNot(contains('api key')));
    expect(doc, isNot(contains('secret')));
  });

  test('ac4 the rollout surface stays reversibly documented', () {
    expect(doc, contains('Disable the relevant feature flag'));
    expect(doc, contains('## Rollback guidance'));
    expect(doc, contains('Preserve user data'));
  });
}
