import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local STT routing and launcher fixtures (#259)',
    () async {
      final result = await Process.run('python3', [
        '-m',
        'unittest',
        'discover',
        '-s',
        'tool',
        '-p',
        'test_stt_shim.py',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    skip: Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'phone audio harness loopback fixtures (#268)',
    () async {
      final result = await Process.run('python3', [
        '-m',
        'unittest',
        'discover',
        '-s',
        'tool',
        '-p',
        'test_phone_audio.py',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    skip: Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'STT benchmark failure accounting fixtures (#270)',
    () async {
      final result = await Process.run('python3', [
        '-m',
        'unittest',
        'discover',
        '-s',
        'tools/stt_bench',
        '-p',
        'test_wer.py',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    skip: Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
