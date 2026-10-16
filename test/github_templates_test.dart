import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the contribution templates so every issue and PR keeps the fields
/// that tie work to acceptance evidence, privacy and rollback.
void main() {
  String read(String path) => File(path).readAsStringSync();

  const issueTemplates = [
    '.github/ISSUE_TEMPLATE/task.md',
    '.github/ISSUE_TEMPLATE/feature_request.md',
    '.github/ISSUE_TEMPLATE/bug_report.md',
  ];

  for (final path in issueTemplates) {
    test('$path has objective, acceptance and validation fields', () {
      final text = read(path);
      expect(text, contains('## Objective'));
      expect(text, contains('## Acceptance criteria'));
      expect(text, contains('- [ ] AC-1:'));
      expect(text, contains('- [ ] AC-2:'));
      expect(text, contains('## CI and validation'));
      expect(text, contains('GitHub-hosted runner: ubuntu-latest'));
      expect(text, contains('- AC-1:'));
      expect(text, contains('- AC-2:'));
      expect(text, contains('docs/acceptance/temporary/issue-<number>.json'));
      expect(text, contains('## Non-goals and runner limits'));
      expect(text, contains('## Definition of done'));
    });
  }

  test('task template separates device-only criteria from hosted CI', () {
    final text = read('.github/ISSUE_TEMPLATE/task.md');
    expect(text, contains('## Non-goals and runner limits'));
    expect(text, contains('Those MUST NOT appear as acceptance criteria.'));
    expect(
      text,
      contains(
        'If indispensable for safe delivery, scope separately and flag as blocked',
      ),
    );
  });

  group('pull request template', () {
    final text = read('.github/PULL_REQUEST_TEMPLATE.md');

    test('Refs for partial work and AutoClose for complete work', () {
      expect(text, contains('Refs #<issue-number>'));
      expect(text, contains('AutoClose #<issue-number>'));
      expect(text, contains('Closes'));
      expect(text, contains('closes immediately on merge'));
    });

    test('links work with Refs and reserves Closes for full acceptance', () {
      expect(
        text,
        contains('link each issue on its own `Refs #<issue-number>` line'),
      );
      expect(
        text,
        contains(
          'only when all original acceptance criteria have executable '
          'evidence and no manual/gap rows remain',
        ),
      );
      expect(
        text,
        contains(
          'GitHub-native `Closes` closes immediately on merge, before main CI',
        ),
      );
      expect(text, contains('avoid it for this workflow'));
      expect(
        text,
        contains(
          '`AutoClose #N` appears on its own line only for complete '
          'criteria; `Refs #N` is used otherwise',
        ),
      );
    });

    test('has acceptance evidence, security, rollback and device sections', () {
      expect(text, contains('## Acceptance criteria evidence'));
      expect(text, contains('## Security, privacy and rollback'));
      expect(text, contains('Rollback:'));
      expect(text, contains('## Manual and device-only evidence'));
      expect(text, contains('## CI and automatic closure'));
    });

    test('forbids privacy gate bypass and unapproved egress', () {
      expect(
        text,
        contains('no privacy gate bypass or unapproved data egress'),
      );
    });
  });

  test('issue template config exists and keeps blank issues explicit', () {
    expect(
      read('.github/ISSUE_TEMPLATE/config.yml'),
      contains('blank_issues_enabled'),
    );
  });
}
