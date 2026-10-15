import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ac2 fail-closed CI gate fixtures are reproducible', () async {
    final interpreter = Platform.isWindows ? 'python' : 'python3';
    final result = await Process.run(
      interpreter,
      [
        '-m',
        'unittest',
        'discover',
        '-s',
        'tool',
        '-p',
        'test_ci_gate.py',
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: 'Gate fixture suite failed (review tool/test_ci_gate.py)',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
