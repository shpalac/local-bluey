import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'AC-1 unsupported simulator mode fails closed before native commands',
    () {
      final result = Process.runSync(
      'bash',
      ['tool/simulator_smoke.sh', 'unsupported-mode'],
    );

      expect(result.exitCode, 2);
      expect(
        result.stderr.toString(),
        contains('unsupported simulator smoke mode: unsupported-mode'),
      );
      expect(result.stdout.toString(), isNot(contains('using simulator')));
    },
  );
}
