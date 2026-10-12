import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('tool/check_coverage.dart').absolute.path;
  late Directory fixture;
  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('coverage-count-fixture-');
  });
  tearDown(() async {
    await fixture.delete(recursive: true);
  });
  Future<ProcessResult> run(String source) async {
    final input = File('${fixture.path}/fixture.info');
    await input.writeAsString(source);
    return Process.run('dart', [script, input.path]);
  }

  String complete(String service) =>
      'SF:lib/services/fabricated.dart\n${service}end_of_record\n'
      'SF:lib/link/fabricated.dart\nLF:100\nLH:65\nend_of_record\n';

  test('actual CLI accepts exact existing60/65 floors', () async {
    final result = await run(complete('LF:100\nLH:60\n'));
    expect(result.exitCode, 0);
    expect(result.stdout, contains('60.0% (60/100) >= floor 60.0%'));
    expect(result.stdout, contains('65.0% (65/100) >= floor 65.0%'));
  });

  test('valid below-floor coverage remains failure1', () async {
    expect((await run(complete('LF:100\nLH:59\n'))).exitCode, 1);
  });

  test(
    'impossible record cannot be hidden by aggregate valid totals',
    () async {
      final result = await run(
        'SF:lib/services/first.dart\nLF:1\nLH:2\nend_of_record\n'
        '${complete('LF:100\nLH:100\n')}',
      );
      expect(result.exitCode, 2);
      expect(result.stdout, isNot(contains('floor')));
      expect(result.stderr, contains('Invalid coverage counts'));
    },
  );

  for (final entry in {
    'negative found': 'LF:-1\nLH:0\n',
    'negative hit': 'LF:1\nLH:-1\n',
    'malformed found': 'LF:not-an-integer\nLH:1\n',
    'missing found': 'LH:1\n',
    'missing hit': 'LF:1\n',
    'duplicate found': 'LF:1\nLF:1\nLH:1\n',
    'duplicate hit': 'LF:1\nLH:1\nLH:1\n',
  }.entries) {
    test('${entry.key} fails as invalid input, no coverage success', () async {
      final result = await run(complete(entry.value));
      expect(result.exitCode, 2);
      expect(result.stdout, isNot(contains('floor')));
    });
  }

  test('valid multiple records aggregate including final EOF record', () async {
    final result = await run(
      'SF:lib/services/first.dart\nLF:10\nLH:6\nend_of_record\n'
      '${complete('LF:90\nLH:54\n')}',
    );
    expect(result.exitCode, 0);
    expect(result.stdout, contains('(60/100)'));
  });

  test(
    'zero counts preserve low-coverage failure, not divide by zero',
    () async {
      expect((await run(complete('LF:0\nLH:0\n'))).exitCode, 1);
    },
  );

  test('out-of-scope count malformed stays outside selectedfloors', () async {
    final result = await run(
      'SF:test/fabricated.dart\nLF:bad\nLH:bad\nend_of_record\n'
      '${complete('LF:100\nLH:60\n')}',
    );
    expect(result.exitCode, 0);
  });
}
