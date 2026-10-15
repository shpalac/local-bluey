import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'CSV-unsafe stage labels fail closed without reflecting the sample',
    () async {
      final directory = await Directory.systemTemp.createTemp('perf-label-');
      try {
        final input = File('${directory.path}/samples.jsonl');
        await input.writeAsString(
          '{"stage":"=HYPERLINK(secret),extra","ms":12}\n',
        );
        final result = await Process.run('dart', [
          'tool/perf_summary.dart',
          input.path,
        ]);
        expect(result.exitCode, 2);
        expect(result.stdout, isEmpty);
        expect(result.stderr, contains('Invalid sample at line 1'));
        expect(result.stderr, isNot(contains('HYPERLINK')));
        expect(result.stderr, isNot(contains('secret')));
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
