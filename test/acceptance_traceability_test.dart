import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProcessResult> validateManifest({
    required Directory root,
    required List<Map<String, Object>> criteria,
  }) async {
    final testDirectory = Directory('${root.path}/test')..createSync();
    File('${testDirectory.path}/sample_test.dart').writeAsStringSync(
      "test('first evidence', () {});\n"
      "test('second evidence', () {});\n",
    );
    File('${root.path}/matrix.json').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'issues': [
          {
            'number': 638,
            'title': 'Traceability contract',
            'criteria': criteria,
          },
        ],
      }),
    );

    return Process.run('python3', [
      'tool/acceptance_criteria.py',
      '--root',
      root.path,
      '--manifest',
      'matrix.json',
      '--out-dir',
      'reports',
    ]);
  }

  Map<String, Object> criterion(String id, String name) => {
    'id': id,
    'requirement': 'Independent acceptance evidence for $id',
    'type': 'automated',
    'tests': [
      {'file': 'test/sample_test.dart', 'name': name},
    ],
  };

  test('traceability rejects one named test claimed by two criteria', () async {
    final root = await Directory.systemTemp.createTemp('traceability-');
    addTearDown(() => root.deleteSync(recursive: true));

    final result = await validateManifest(
      root: root,
      criteria: [
        criterion('ac_1', 'first evidence'),
        criterion('ac_2', 'first evidence'),
      ],
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains('duplicate evidence ownership'));
  });

  test('traceability accepts independently named criterion evidence', () async {
    final root = await Directory.systemTemp.createTemp('traceability-');
    addTearDown(() => root.deleteSync(recursive: true));

    final result = await validateManifest(
      root: root,
      criteria: [
        criterion('ac_1', 'first evidence'),
        criterion('ac_2', 'second evidence'),
      ],
    );

    expect(result.exitCode, 0);
    final report = jsonDecode(
      File('${root.path}/reports/acceptance.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(report['issueCompletionCertified'], isFalse);
  });
}
