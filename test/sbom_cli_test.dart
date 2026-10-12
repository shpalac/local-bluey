import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Actual offline CLI fixtures only. No license evaluation, schema certification,
// source/archive authenticity, native inventory or SDK identity claim.
void main() {
  final script = File('tool/sbom.dart').absolute.path;
  late Directory fixture;

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('sbom-fixture-');
  });
  tearDown(() async {
    await fixture.delete(recursive: true);
  });

  Future<ProcessResult> run({String output = 'result.json'}) =>
      Process.run('dart', [script, output], workingDirectory: fixture.path);
  Future<void> lock(String source) =>
      File('${fixture.path}/pubspec.lock').writeAsString(source);
  Future<Map<String, dynamic>> result() async =>
      jsonDecode(await File('${fixture.path}/result.json').readAsString())
          as Map<String, dynamic>;

  test('actual CLI emits resolved components, not pubspec ranges', () async {
    await lock('''
packages:
  fabricated:
    dependency: "direct main"
    source: hosted
    version: "2.3.4"
sdks:
  dart: ">=3.0.0"
''');
    final process = await run();
    expect(process.exitCode, 0);
    final document = await result();
    expect(document['bomFormat'], 'CycloneDX');
    expect(document['specVersion'], '1.6');
    expect(document['components'], [
      {
        'type': 'library',
        'bom-ref': 'pkg:pub/fabricated@2.3.4',
        'name': 'fabricated',
        'version': '2.3.4',
        'purl': 'pkg:pub/fabricated@2.3.4',
      },
    ]);
    expect(process.stdout, contains('1 packages'));
  });

  test('empty package map has no fabricated dependencies', () async {
    await lock('packages:\nsdks:\n  dart: ">=3.0.0"\n');
    expect((await run()).exitCode, 0);
    expect((await result())['components'], isEmpty);
  });

  test(
    'repeat CLI runs preserve components, timestamp is diagnostic',
    () async {
      await lock(
        'packages:\n  first:\n    version: "1.0.0"\n'
        '  second:\n    version: "4.5.6"\n',
      );
      expect((await run()).exitCode, 0);
      final first = await result();
      expect((await run()).exitCode, 0);
      final second = await result();
      expect(second['components'], first['components']);
      expect((second['components'] as List).length, 2);
      expect(
        DateTime.tryParse(second['metadata']['timestamp'] as String),
        isNotNull,
      );
    },
  );

  test('missing lock fails, produces no complete output', () async {
    expect((await run()).exitCode, isNot(0));
    expect(await File('${fixture.path}/result.json').exists(), isFalse);
  });

  test('output directory missing fails, no success count is printed', () async {
    await lock('packages:\n');
    final process = await run(output: 'missing/result.json');
    expect(process.exitCode, isNot(0));
    expect(process.stdout, isNot(contains('SBOM:')));
    expect(await File('${fixture.path}/missing/result.json').exists(), isFalse);
  });
}
