import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/execution_audit.dart';

void main() {
  test('stop blocks the next step', () {
    final audit = ExecutionAudit();
    expect(audit.canStartNextStep, isTrue);
    audit.requestStop();
    expect(audit.canStartNextStep, isFalse);
    expect(audit.entries.last.status, 'stopped');
  });

  test('unknown fields and diagnostics are redacted', () {
    final audit = ExecutionAudit();
    audit.record('password=secret', 'token=secret', diagnostic: 'secret');
    expect(audit.exportRedacted(consent: true), isNot(contains('secret')));
  });

  test('export fails closed without consent', () {
    final audit = ExecutionAudit();
    expect(() => audit.exportRedacted(consent: false), throwsStateError);
  });

  test('bounded memory and valid JSON', () {
    final audit = ExecutionAudit(maxEntries: 2);
    for (var i = 0; i < 5; i++) {
      audit.record('execution', 'completed');
    }
    expect(jsonDecode(audit.exportRedacted(consent: true)), hasLength(2));
  });
}
