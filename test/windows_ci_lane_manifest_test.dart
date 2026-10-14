import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File('.github/workflows/windows-ci-lane.yml')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('Windows CI lane manifest is deterministic', () {
    expect(workflow, contains('runs-on: windows-latest'));
    expect(workflow, contains('flutter test test/windows_ci_lane_manifest_test.dart'));
    expect(workflow, contains('pull_request:'));
    expect(workflow, isNot(contains('pull_request_target')));
  });

  test('Windows CI lane manifest is least privilege and pinned', () {
    expect(workflow, contains('permissions:\n  contents: read'));
    expect(workflow, contains('actions/checkout@11d5960a326750d5838078e36cf38b85af677262'));
    expect(workflow, contains('subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2'));
    expect(workflow, isNot(contains('secrets.')));
    expect(workflow, isNot(contains('curl ')));
    expect(workflow, isNot(contains('wget ')));
  });
}
