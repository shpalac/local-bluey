import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Validates documentation evidence, not feature completion or ADR approval.
void _validateRegistry(Map<String, dynamic> registry) {
  if (registry['version'] != 1 || registry['adrs'] is! List) {
    throw const FormatException('Unsupported ADR registry version or shape');
  }

  final ids = <String>{};
  for (final raw in registry['adrs'] as List) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid ADR entry');
    }
    final id = raw['id'];
    final path = raw['path'];
    final status = raw['status'];
    if (id is! String ||
        !RegExp(r'^ADR-\d{3}$').hasMatch(id) ||
        !ids.add(id) ||
        status is! String ||
        !{'planning', 'proposed', 'accepted', 'superseded'}.contains(status) ||
        path is! String ||
        !_safePath(path) ||
        !path.startsWith('docs/adr/')) {
      throw const FormatException('Invalid or duplicate ADR identity');
    }

    final decisions = raw['decisions'];
    if (decisions is! List || decisions.isEmpty) {
      throw const FormatException('Missing decision links');
    }
    final numbers = <int>{};
    for (final rawDecision in decisions) {
      if (rawDecision is! Map<String, dynamic>) {
        throw const FormatException('Invalid decision');
      }
      final number = rawDecision['number'];
      final title = rawDecision['decision'];
      final coverage = rawDecision['coverage'];
      final issue = rawDecision['issue'];
      final source = rawDecision['source'];
      final testPath = rawDecision['test'];
      if (number is! int ||
          number < 1 ||
          !numbers.add(number) ||
          title is! String ||
          title.trim().isEmpty ||
          !{'planned', 'contract'}.contains(coverage) ||
          issue is! int ||
          issue < 1 ||
          source is! String ||
          !_safePath(source) ||
          !(source.startsWith('lib/') || source.startsWith('.github/')) ||
          testPath is! String ||
          !_safePath(testPath) ||
          !(testPath.startsWith('test/') || testPath.startsWith('tool/'))) {
        throw const FormatException('Invalid or unsafe decision link');
      }
    }
    for (var number = 1; number <= numbers.length; number++) {
      if (!numbers.contains(number)) {
        throw const FormatException('Noncontiguous numbered decisions');
      }
    }
  }
}

bool _safePath(String path) {
  return path.isNotEmpty &&
      path.length < 256 &&
      RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(path) &&
      !path.startsWith('/') &&
      !path.split('/').any((segment) => segment == '..' || segment.isEmpty);
}

Map<String, dynamic> _registry() =>
    jsonDecode(File('docs/adr/traceability.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test(
    'indexes all numbered decisions with real implementation boundaries',
    () {
      final registry = _registry();
      expect(() => _validateRegistry(registry), returnsNormally);

      final adrs = registry['adrs'] as List;
      final tracked = <String>{};
      for (final raw in adrs) {
        final adr = raw as Map<String, dynamic>;
        final path = adr['path'] as String;
        expect(File(path).existsSync(), isTrue, reason: path);
        tracked.add(path);
        final doc = File(path).readAsStringSync();
        for (final rawDecision in adr['decisions'] as List) {
          final decision = rawDecision as Map<String, dynamic>;
          final number = decision['number'] as int;
          expect(
            doc,
            contains(RegExp('^$number\\. ', multiLine: true)),
            reason: '${adr['id']} decision $number must exist in its ADR',
          );
          for (final key in ['source', 'test']) {
            final linked = decision[key] as String;
            expect(File(linked).existsSync(), isTrue, reason: linked);
          }
        }
      }

      final committed = Directory('docs/adr')
          .listSync()
          .whereType<File>()
          .map((file) => file.path.replaceAll('\\', '/'))
          .where(
            (path) =>
                RegExp(r'docs/adr/(ADR-\d{3}|\d{3})-.*\.md$').hasMatch(path),
          )
          .toSet();
      expect(tracked, committed, reason: 'No ADR may escape the registry');
    },
  );

  test('preserves proposals and planning status without claiming approval', () {
    final registry = _registry();
    final byId = {
      for (final raw in registry['adrs'] as List)
        (raw as Map<String, dynamic>)['id']: raw,
    };
    expect((byId['ADR-001'] as Map)['status'], 'planning');
    expect((byId['ADR-002'] as Map)['status'], 'proposed');

    final planning = File('docs/adr/ADR-001-bluey-delivery-decisions.md')
        .readAsStringSync();
    final proposed = File('docs/adr/002-observation-privacy.md')
        .readAsStringSync();
    expect(planning, contains('Accepted for implementation planning'));
    expect(proposed, contains('not ratified'));
    final index = File('docs/adr/README.md').readAsStringSync();
    expect(index, contains('**not** necessarily a complete feature'));
    expect(index, contains('not ratified'));
  });

  test('rejects unsafe paths duplicate IDs and missing decisions', () {
    expect(_safePath('../secrets'), isFalse);
    expect(_safePath('/etc/passwd'), isFalse);
    expect(_safePath('docs//adr/a.md'), isFalse);
    expect(_safePath('https://example.com'), isFalse);

    final registry = _registry();
    final duplicate = jsonDecode(jsonEncode(registry)) as Map<String, dynamic>;
    final entries = duplicate['adrs'] as List;
    entries.add(jsonDecode(jsonEncode(entries.first)));
    expect(() => _validateRegistry(duplicate), throwsFormatException);

    final missing = jsonDecode(jsonEncode(registry)) as Map<String, dynamic>;
    final decisions =
        ((missing['adrs'] as List).first as Map<String, dynamic>)['decisions']
            as List;
    decisions.removeAt(1);
    expect(() => _validateRegistry(missing), throwsFormatException);

    final traversal = jsonDecode(jsonEncode(registry)) as Map<String, dynamic>;
    final first =
        ((traversal['adrs'] as List).first as Map<String, dynamic>)['decisions']
            as List;
    (first.first as Map<String, dynamic>)['source'] = '../outside.dart';
    expect(() => _validateRegistry(traversal), throwsFormatException);
  });

  test('acceptance map and ADR template document review and rollback', () {
    final acceptance = File('docs/ACCEPTANCE_MAP.md').readAsStringSync();
    final template = File('docs/adr/ADR-TEMPLATE.md').readAsStringSync();
    final index = File('docs/adr/README.md').readAsStringSync();
    expect(acceptance, contains('BLU-076 / #634'));
    expect(acceptance, contains('docs/adr/traceability.json'));
    expect(template, contains('## Security and privacy'));
    expect(template, contains('## Rollout, migration and rollback'));
    expect(template, contains('## Approval record'));
    expect(index, contains('flutter test test/issues/issue_634_test.dart'));
    expect(index, contains('To roll back'));
  });
}
