import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<void> runOfflineFixture(String fixtureName) async {
  final result = await Process.run('python3', [
    '-m',
    'unittest',
    'discover',
    '-s',
    'tools/stt_bench',
    '-p',
    'test_issue_580.py',
    '-k',
    fixtureName,
  ]);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

void main() {
  test(
    'issue 580 AC-1 Hebrew baseline is reproducible',
    () => runOfflineFixture('test_hebrew_nikud_and_punctuation_baseline_reproducible'),
    skip: Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'issue 580 AC-2 empty successful STT output fails closed',
    () => runOfflineFixture('test_empty_success_transcript_is_incomplete'),
    skip: Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
