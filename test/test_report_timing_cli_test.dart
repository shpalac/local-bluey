import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('tool/test_report.dart').absolute.path;
  late Directory fixture;
  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('test-report-timing-');
  });
  tearDown(() async => fixture.delete(recursive: true));
  Map<String, dynamic> start(int id, int time) => {
    'type': 'testStart',
    'time': time,
    'test': {'id': id, 'name': 'fabricated$id', 'suiteID': 1},
  };
  Map<String, dynamic> done(int id, int time, {bool hidden = false}) => {
    'type': 'testDone',
    'time': time,
    'testID': id,
    'result': 'success',
    'hidden': hidden,
  };
  Future<ProcessResult> run(List<Map<String, dynamic>> events) async {
    final file = File('${fixture.path}/events.jsonl');
    await file.writeAsString(events.map(jsonEncode).join('\n'));
    return Process.run('dart', [script, file.path]);
  }

  test('actual CLI computes elapsed durations for interleaved tests', () async {
    final result = await run([
      start(1, 100),
      start(2, 200),
      done(2, 400),
      done(1, 500),
    ]);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('0.6 s summed test time'));
    expect(result.stdout, contains('| fabricated1 | 400 |'));
    expect(result.stdout, contains('| fabricated2 | 200 |'));
  });
  test(
    'zero duration remains valid, hidden completions do not count',
    () async {
      final result = await run([
        start(1, 100),
        done(1, 100),
        done(2, 150, hidden: true),
      ]);
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains('1 tests, 0 failed, 0.0 s summed test time'),
      );
    },
  );
  for (final entry in {
    'negative start': [start(1, -1), done(1, 100)],
    'completion before start': [start(1, 200), done(1, 100)],
    'missing start': [done(1, 100)],
    'duplicate start': [start(1, 100), start(1, 200), done(1, 300)],
    'duplicate completion': [start(1, 100), done(1, 200), done(1, 300)],
  }.entries) {
    test(
      '${entry.key} is explicit invalid timing, no misleading report',
      () async {
        final result = await run(entry.value);
        expect(result.exitCode, 2);
        expect(result.stderr, contains('Invalid test'));
        expect(result.stdout, isEmpty);
      },
    );
  }
}
