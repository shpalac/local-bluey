import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final protocol = File('docs/MAC_PILOT_PROTOCOL.md').readAsStringSync();

  test('pilot protocol explicitly requires opt-in and safe stop', () {
    expect(protocol, contains('Default OFF'));
    expect(protocol, contains('affirmative consent'));
    expect(protocol, contains('Revoke consent'));
    expect(protocol, contains('No automatic actions'));
    expect(protocol, contains('SafetyGate'));
    expect(protocol, contains('Rollback'));
  });

  test('pilot protocol records privacy performance and manual gaps', () {
    for (final required in <String>[
      'False suggestion rate',
      'Privacy incidents',
      'CPU:',
      'Retained data:',
      'Permission denied/revoked',
      'Offline',
      'timeout',
      'restart',
      'RTL',
      'NO-GO until signed',
      'not yet conducted',
    ]) {
      expect(protocol.toLowerCase(), contains(required.toLowerCase()));
    }
  });
}
