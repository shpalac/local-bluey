import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test('runner only instructions and templates', () {
    final agents = source('AGENTS.md').toLowerCase();
    expect(agents, contains('github-hosted'));
    expect(agents, contains('acceptance'));
    for (final path in [
      '.github/ISSUE_TEMPLATE/task.md',
      '.github/ISSUE_TEMPLATE/feature_request.md',
      '.github/ISSUE_TEMPLATE/bug_report.md',
    ]) {
      final template = source(path).toLowerCase();
      expect(template, contains('github-hosted'), reason: path);
      expect(template, contains('ac-1'), reason: path);
    }
  });

  test('new issue validator and fixtures', () {
    final validator = source('tool/runner_only_issue_contract.py');
    final hygiene = source('tool/issue_task_hygiene.py');
    final fixtures = source('tool/test_runner_only_issue_contract.py');
    expect(validator, contains('validate_runner_only_contract'));
    expect(validator, contains('NOT_RUNNABLE'));
    expect(validator, contains('PLAN.findall'));
    expect(hygiene, contains('validate_runner_only_contract'));
    expect(fixtures, contains('unittest'));
  });

  test('deferred closure documentation', () {
    final agents = source('AGENTS.md');
    final lifecycle = source('docs/acceptance/TASK_LIFECYCLE.md');
    expect(agents, contains('Refs #'));
    expect(agents, contains('AutoClose #'));
    expect(lifecycle, contains('AutoClose #'));
    expect(lifecycle, contains('Refs #'));
  });

  test('closure safeguard fixtures', () {
    final close = source('tool/issue_auto_close.py');
    final merge = source('tool/issue_auto_merge.py');
    final closeTests = source('tool/test_issue_auto_close.py');
    final mergeTests = source('tool/test_issue_auto_merge.py');
    expect(close, contains('def '));
    expect(merge, contains('def '));
    expect(closeTests, contains('unittest'));
    expect(mergeTests, contains('unittest'));
  });
}
