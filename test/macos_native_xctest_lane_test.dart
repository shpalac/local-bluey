import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS XCTest target runs after Flutter debug build', () {
    final workflow =
        File('.github/workflows/macos-native-build-lane.yml').readAsStringSync();
    final nativeTest =
        File('macos/RunnerTests/RunnerTests.swift').readAsStringSync();
    final project =
        File('macos/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(workflow, contains('runs-on: macos-latest'));
    expect(workflow, contains('xcodebuild test'));
    expect(workflow, contains('-workspace macos/Runner.xcworkspace'));
    expect(workflow, contains('-scheme Runner'));
    expect(workflow, contains('-only-testing:RunnerTests'));
    expect(workflow, contains('CODE_SIGNING_ALLOWED=NO'));
    expect(
      workflow.indexOf('flutter build macos --debug'),
      lessThan(workflow.indexOf('xcodebuild test')),
    );
    expect(project, contains('RunnerTests.swift in Sources'));
    expect(
      nativeTest,
      contains('func testAppDelegateTerminatesWhenLastWindowCloses()'),
    );
    expect(
      nativeTest,
      contains('delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)'),
    );
  });
}
