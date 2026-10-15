import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rollback does not disable SafetyGate confirmations', () {
    final guide = File('docs/BLU-035-rollout-rollback.md').readAsStringSync();
    final source = File('lib/services/safety_gate.dart').readAsStringSync();

    expect(guide, contains('SafetyGate.setEnabled(false)'));
    expect(guide, contains('not** a feature-specific rollback switch'));
    expect(guide, contains('Keep SafetyGate enabled'));
    expect(guide, contains('verify subsequent risky actions still require approval'));
    expect(source, contains('Future<void> setEnabled(bool value)'));
    expect(source, contains('if (!enabled) return true;'));
    expect(source, contains('if (confirm == null || stale()) return false;'));
  });
}
