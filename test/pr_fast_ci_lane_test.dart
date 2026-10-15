import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BLU-037: structural guard for the PR fast CI lane workflow. It checks what
/// the file itself declares. That the job is a *required* status is branch
/// protection configuration and is not verifiable from the repository.
void main() {
  final text = File('.github/workflows/pr-fast-ci.yml').readAsStringSync();

  test(
    'fast lane runs on pull requests to main without privileged triggers',
    () {
      expect(text, contains('pull_request:'));
      expect(text, contains('branches: [main]'));
      expect(text, isNot(contains('pull_request_target')));
      expect(text, isNot(contains('workflow_run')));
    },
  );

  test('fast lane has read-only permissions and no secrets', () {
    expect(text, contains('permissions:\n  contents: read'));
    expect(text, isNot(contains('secrets.')));
    expect(text, isNot(contains('write')));
  });

  // Preserve the BLU-037 acceptance-test name while verifying its
  // responsibilities are delegated to the required central CI build gate.
  test('fast lane runs format, analyze and the full test suite', () {
    final centralCi = File('.github/workflows/ci.yml').readAsStringSync();

    expect(text, contains('name: Fast CI (format analyze test)'));
    expect(text, contains('test_ci_impact.py'));
    expect(text, contains('test_ci_gate.py'));
    expect(text, isNot(contains('flutter analyze')));
    expect(text, isNot(contains('flutter test')));

    expect(centralCi, contains('      - name: Format check'));
    expect(centralCi, contains('dart format lib test'));
    expect(centralCi, contains('run: flutter analyze'));
    expect(centralCi, contains('flutter test --coverage --reporter expanded'));
    expect(centralCi, contains('run: python3 tool/ci_gate.py'));
    expect(
      centralCi,
      contains('needs: [detect, static, docs, acceptance-evidence, test,'),
    );
  });

  test('fast lane actions are pinned to full commit SHAs', () {
    final uses = RegExp(r'uses:\s*(\S+)').allMatches(text).toList();
    expect(uses, isNotEmpty);
    for (final m in uses) {
      expect(
        RegExp(r'@[0-9a-f]{40}$').hasMatch(m.group(1)!),
        isTrue,
        reason: m.group(1),
      );
    }
  });
}
