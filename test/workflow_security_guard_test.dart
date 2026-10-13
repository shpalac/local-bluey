import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard over .github/workflows (#599, BLU-043). It reads workflow
/// text only; it does not run Actions and cannot see repository settings.
void main() {
  final workflows =
      Directory('.github/workflows')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  String name(File f) => f.uri.pathSegments.last;

  /// Lines of the top-level `permissions:` block, or null if absent.
  List<String>? topLevelPermissions(String text) {
    final lines = text.split('\n');
    final start = lines.indexOf('permissions:');
    if (start < 0) return null;
    final block = <String>[];
    for (final line in lines.skip(start + 1)) {
      if (line.startsWith('  ') && line.trim().isNotEmpty) {
        block.add(line.trim());
      } else if (line.trim().isEmpty || line.trim().startsWith('#')) {
        continue;
      } else {
        break;
      }
    }
    return block;
  }

  /// Top-level write scopes each workflow is allowed to hold. Anything else
  /// needs a deliberate change here, in review.
  const allowedTopLevelWrites = {
    'ci-metrics.yml': {'issues'},
    'flutter-version-check.yml': {'issues'},
    'issue-task-hygiene.yml': {'issues'},
  };

  test('finds the workflow files', () {
    expect(workflows, isNotEmpty);
  });

  for (final f in workflows) {
    final text = f.readAsStringSync();

    test('${name(f)} declares top-level permissions', () {
      expect(topLevelPermissions(text), isNotNull);
    });

    test('${name(f)} top-level write scopes are allowlisted', () {
      final block = topLevelPermissions(text) ?? const <String>[];
      final writes = {
        for (final l in block)
          if (l.endsWith(': write')) l.split(':').first,
      };
      expect(
        writes.difference(allowedTopLevelWrites[name(f)] ?? const {}),
        isEmpty,
        reason: 'unexpected top-level write permission in ${name(f)}',
      );
      expect(block.any((l) => l.startsWith('write-all')), isFalse);
    });

    test('${name(f)} avoids privileged PR triggers and inherited secrets', () {
      expect(text, isNot(contains('pull_request_target')));
      expect(text, isNot(contains('secrets: inherit')));
    });
  }

  group('pinned actions script', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('pinned-actions-fixture-');
    });
    tearDown(() async {
      await dir.delete(recursive: true);
    });

    Future<ProcessResult> check(String yaml) async {
      await File('${dir.path}/w.yml').writeAsString(yaml);
      return Process.run('bash', [
        '.github/scripts/check-pinned-actions.sh',
        dir.path,
      ]);
    }

    const sha = '0123456789abcdef0123456789abcdef01234567';

    test('real workflows pass', () async {
      final r = await Process.run('bash', [
        '.github/scripts/check-pinned-actions.sh',
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test('movable tag fails in list and bare forms', () async {
      expect((await check('      - uses: actions/checkout@v4\n')).exitCode, 1);
      expect(
        (await check('        uses: actions/checkout@main\n')).exitCode,
        1,
      );
    });

    test('full SHA with version comment passes', () async {
      expect(
        (await check('      - uses: actions/checkout@$sha # v4\n')).exitCode,
        0,
      );
    });

    test('short SHA fails', () async {
      expect(
        (await check('      - uses: actions/checkout@0123456\n')).exitCode,
        1,
      );
    });
  });
}
