import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the incident runbook tied to the release pipeline it describes and
/// to its honesty limits.
void main() {
  final runbook = File('docs/INCIDENT_RUNBOOK.md').readAsStringSync();
  final release = File('.github/workflows/release.yml').readAsStringSync();

  test('covers the four incident classes', () {
    for (final heading in [
      '## 1. Bad release',
      '## 2. Leaked secret',
      '## 3. Broken CI or required check',
      '## 4. Privacy-affecting defect',
    ]) {
      expect(runbook, contains(heading));
    }
  });

  test('describes the pipeline that release.yml actually has', () {
    expect(release, contains("tags: ['v*.*.*']"));
    expect(release, contains('environment: release'));
    expect(runbook, contains('`v*.*.*`'));
    expect(runbook, contains('`release` environment'));
    expect(runbook, contains('gh attestation verify'));
  });

  test('requires owner approval for external changes and bans bypasses', () {
    expect(runbook, contains('Approval rule'));
    expect(runbook, contains('owner action'));
    expect(runbook, contains('Never reuse or move an existing tag'));
    expect(runbook, contains('Do not skip checks'));
    expect(runbook, contains('admin bypass'));
  });

  test('states what it does not cover and invents no privacy policy', () {
    expect(runbook, contains('## What this runbook does not cover'));
    expect(runbook, contains('#351'));
    expect(runbook, contains('Do not invent a policy'));
  });

  test('linked docs exist', () {
    for (final path in [
      'docs/RELEASE.md',
      'docs/SECRETS.md',
      'docs/FLAKE_POLICY_PLAN.md',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
      expect(runbook, contains(path));
    }
  });
}
