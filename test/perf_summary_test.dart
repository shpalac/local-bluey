import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('tool/perf_summary.dart').absolute.path;
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('perf-summary-fixture-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<ProcessResult> run(String content) async {
    final input = File('${dir.path}/perf.jsonl');
    await input.writeAsString(content);
    return Process.run('dart', [script, input.path]);
  }

  String sample(String stage, int ms) =>
      '{"stage":"$stage","ms":$ms,"at":"2026-01-01T00:00:00.000"}\n';

  test('prints nearest-rank p50 and p95 per stage, sorted by name', () async {
    final lines = StringBuffer();
    for (var i = 1; i <= 20; i++) {
      lines.write(sample('thinking.brain', i * 100));
    }
    lines.write(sample('idle', 7));
    final result = await run(lines.toString());
    expect(result.exitCode, 0);
    expect((result.stdout as String).trim().split('\n'), [
      'stage,count,p50_ms,p95_ms',
      'idle,1,7,7',
      'thinking.brain,20,1000,1900',
    ]);
  });

  test('order of samples does not change the result', () async {
    final a = await run(sample('s', 30) + sample('s', 10) + sample('s', 20));
    final b = await run(sample('s', 10) + sample('s', 20) + sample('s', 30));
    expect(a.stdout, b.stdout);
    expect(a.stdout, contains('s,3,20,30'));
  });

  test('blank lines are ignored', () async {
    final result = await run('\n${sample('s', 5)}\n');
    expect(result.exitCode, 0);
    expect(result.stdout, contains('s,1,5,5'));
  });

  for (final bad in [
    'not json\n',
    '{"stage":"s"}\n',
    '{"stage":"s","ms":-1}\n',
    '{"stage":"s","ms":1.5}\n',
    '{"stage":"","ms":1}\n',
    '[1,2]\n',
  ]) {
    test('invalid line fails with line number only: ${bad.trim()}', () async {
      final result = await run(sample('ok', 1) + bad);
      expect(result.exitCode, 2);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('Invalid sample at line 2'));
      expect(result.stderr, isNot(contains('not json')));
    });
  }

  test('empty input and missing file fail with exit 2', () async {
    expect((await run('')).exitCode, 2);
    final missing = await Process.run('dart', [script, '${dir.path}/none']);
    expect(missing.exitCode, 2);
  });
}
