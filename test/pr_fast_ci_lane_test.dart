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

  test('fast lane runs format, analyze and the full test suite', () {
    expect(
      text,
      contains('dart format --output=none --set-exit-if-changed lib test'),
    );
    expect(text, contains('flutter analyze'));
    expect(text, contains('flutter test'));
    expect(text, contains('flutter pub get --enforce-lockfile'));
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
