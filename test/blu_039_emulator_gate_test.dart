import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File('.github/workflows/ci.yml').readAsStringSync();
  final start = workflow.indexOf('\n  android-integration:');
  final end = workflow.indexOf('\n  linux:', start);
  final lane = start < 0
      ? ''
      : workflow.substring(start, end < 0 ? workflow.length : end);

  test('ac2 Android emulator failures remain explicit and required', () {
    expect(start, greaterThan(0));
    expect(lane, contains('reactivecircus/android-emulator-runner@'));
    expect(lane, contains('flutter test integration_test'));
    expect(workflow, contains('android-integration, linux, security'));
    expect(workflow, contains('python3 tool/ci_gate.py'));
    expect(workflow, isNot(contains('continue-on-error: true')));
  });
}
