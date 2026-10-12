import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('tool/test_report.dart').absolute.path;
  late Directory fixture;
  setUp(
    () async =>
        fixture = await Directory.systemTemp.createTemp('report-order-'),
  );
  tearDown(() async => fixture.delete(recursive: true));
  Map<String, dynamic> suite(int id, String path) => {
    'type': 'suite',
    'suite': {'id': id, 'path': path},
  };
  Map<String, dynamic> start(int id) => {
    'type': 'testStart',
    'time': 10,
    'test': {'id': id, 'name': 'fabricated$id', 'suiteID': id},
  };
  Map<String, dynamic> done(int id) => {
    'type': 'testDone',
    'time': 30,
    'testID': id,
    'result': 'failure',
    'hidden': false,
  };
  Future<ProcessResult> run(List<int> order, {bool files = false}) async {
    final path = File('${fixture.path}/events.jsonl');
    await path.writeAsString(
      [
        suite(1, '/fabricated/test/z_test.dart'),
        suite(2, '/fabricated/test/a_test.dart'),
        start(1),
        start(2),
        ...order.map(done),
      ].map(jsonEncode).join('\n'),
    );
    return Process.run('dart', [
      script,
      path.path,
      if (files) '--failed-files',
    ]);
  }

  test(
    'equal durations and failures are independent of completion interleaving',
    () async {
      final a = await run([1, 2]);
      final b = await run([2, 1]);
      expect(a.exitCode, 0);
      expect(b.exitCode, 0);
      expect(a.stdout, b.stdout);
      final report = a.stdout as String;
      expect(
        report.indexOf('| fabricated1 |'),
        lessThan(report.indexOf('| fabricated2 |')),
      );
      expect(
        report.indexOf('- fabricated1 '),
        lessThan(report.indexOf('- fabricated2 ')),
      );
    },
  );
  test(
    'failed files sorted by relative path, independent of completion order',
    () async {
      final a = await run([1, 2], files: true);
      final b = await run([2, 1], files: true);
      expect(a.exitCode, 0);
      expect(b.exitCode, 0);
      expect(a.stdout, 'test/a_test.dart test/z_test.dart\n');
      expect(a.stdout, b.stdout);
    },
  );
}
