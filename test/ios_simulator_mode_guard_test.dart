import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AC-1 invalid simulator mode fails closed', () {
    const script = 'tool/simulator_smoke.sh';
    final result = Process.runSync('bash', [script, 'bad']);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('unsupported simulator smoke mode: bad'));
  });
}
