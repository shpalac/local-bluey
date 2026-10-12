import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('tool/test_report.dart').absolute.path;
  late Directory fixture;
  setUp(
    () async =>
        fixture = await Directory.systemTemp.createTemp('report-errors-'),
  );
  tearDown(() async => fixture.delete(recursive: true));
  final suite = {
    'type': 'suite',
    'suite': {'id': 1, 'path': '/fabricated/test/sample_test.dart'},
  };
  final start = {
    'type': 'testStart',
    'time': 100,
    'test': {'id': 1, 'name': 'fabricated case', 'suiteID': 1},
  };
  Map<String, dynamic> done({bool hidden = false}) => {
    'type': 'testDone',
    'time': 300,
    'testID': 1,
    'result': 'success',
    'hidden': hidden,
  };
  Map<String, dynamic> error(Object? id) => {
    'type': 'error',
    'testID': id,
    'error': 'fabricated-secret-error',
    'stackTrace': 'fabricated-private-stack',
  };
  Future<ProcessResult> run(
    List<Map<String, dynamic>> events, {
    bool files = false,
  }) async {
    final path = File('${fixture.path}/events.jsonl');
    await path.writeAsString(events.map(jsonEncode).join('\n'));
    return Process.run('dart', [
      script,
      path.path,
      if (files) '--failed-files',
    ]);
  }

  for (final hidden in [false, true]) {
    test('late error exposes hidden=$hidden completion exactly once', () async {
      final result = await run([
        suite,
        start,
        done(hidden: hidden),
        error(1),
        error(1),
      ]);
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains('1 tests, 1 failed, 0.2 s summed test time'),
      );
      expect(
        result.stdout,
        contains('- fabricated case (test/sample_test.dart)'),
      );
      expect(result.stdout, isNot(contains('fabricated-secret-error')));
      expect(result.stdout, isNot(contains('fabricated-private-stack')));
    });
  }
  test('error before successful completion still fails the case', () async {
    final result = await run([suite, start, error(1), done()]);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('1 tests, 1 failed'));
  });
  test('hidden success stays excluded', () async {
    final result = await run([suite, start, done(hidden: true)]);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('0 tests, 0 failed'));
  });
  test('late hidden error contributes failed-file identity once', () async {
    final result = await run([
      suite,
      start,
      done(hidden: true),
      error(1),
      error(1),
    ], files: true);
    expect(result.exitCode, 0);
    expect(result.stdout, 'test/sample_test.dart\n');
  });
  for (final id in [2, '1', null]) {
    test('invalid error identity $id fails before output', () async {
      final result = await run([suite, start, done(), error(id)]);
      expect(result.exitCode, 2);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('Invalid test error identity'));
    });
  }
  test('error without completed timing fails before output', () async {
    final result = await run([suite, start, error(1)]);
    expect(result.exitCode, 2);
    expect(result.stdout, isEmpty);
    expect(result.stderr, contains('Invalid test error completion'));
  });
}
