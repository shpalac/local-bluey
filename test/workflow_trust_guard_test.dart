import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('workflow-trust-');
  });

  tearDown(() async {
    await fixture.delete(recursive: true);
  });

  Future<ProcessResult> check(String path) {
    return Process.run('python3', ['tool/check_workflow_trust.py', path]);
  }

  test('privileged pull request trigger fails closed', () async {
    final workflow = File('${fixture.path}/untrusted.yml');
    await workflow.writeAsString(
      'name: untrusted\n'
      'on:\n'
      '  pull_request_target:\n'
      'jobs:\n'
      '  bad:\n'
      '    secrets: inherit\n',
    );

    final result = await check(fixture.path);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('pull_request_target is forbidden'));
    expect(result.stderr, contains('inherited secrets are forbidden'));
    expect(result.stderr, isNot(contains('name: untrusted')));
  });

  test('missing workflow directory yields actionable failure', () async {
    final result = await check('${fixture.path}/not-present');

    expect(result.exitCode, 1);
    expect(result.stderr, contains('workflow directory missing'));
  });

  test('real workflows pass the wired trust guard', () async {
    final result = await check('.github/workflows');

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });
}
