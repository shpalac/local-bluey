import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/support_matrix.dart';

/// Refs #661. Pins the current Linux policy so code and README cannot
/// drift apart: Linux is unsupported, advertises no host capability, and
/// the README makes no character-parity claim. Changing the policy (an
/// owner decision) means changing this test on purpose.
void main() {
  final linux = SupportMatrix.profile(operatingSystem: 'linux');

  test('Linux is recorded as unsupported, not host or client', () {
    expect(linux.role, AppRole.unsupported);
  });

  test('Linux advertises no host or phone-server capability', () {
    for (final c in [
      SupportMatrix.hostControl,
      SupportMatrix.windowManagement,
      SupportMatrix.phoneServer,
      SupportMatrix.macLink,
    ]) {
      expect(linux.capabilities, isNot(contains(c)), reason: c);
    }
  });

  test('Linux has an unsupported reason that names the role', () {
    expect(SupportMatrix.unsupportedReason(linux), isNotEmpty);
  });

  test('README Linux row matches the policy and claims no parity', () {
    final rows = File('README.md')
        .readAsLinesSync()
        .where((l) => l.startsWith('| **Linux**'))
        .toList();
    expect(rows, hasLength(1));
    final row = rows.single.toLowerCase();
    expect(row, contains('unsupported'));
    expect(row, isNot(contains('parity')));
    expect(row, isNot(contains('host |')));
    expect(row, isNot(contains('supported host')));
  });
}
