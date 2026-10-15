import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BLU-038: structural checks on the macOS native build lane workflow file.
/// They do not prove the lane builds on a macOS runner; that evidence comes
/// from the lane's own CI run.
void main() {
  final text = File('.github/workflows/macos-native-build-lane.yml')
      .readAsStringSync();

  // This acceptance test name is referenced by the BLU-038 manifest.
  // The Flutter build and Dart tests moved to central CI; the native lane
  // retains XCTest, which is independently exercised on a macOS runner.
  test('macOS build lane manifest is deterministic', () {
    final centralCi = File('.github/workflows/ci.yml').readAsStringSync();

    expect(text, contains('runs-on: macos-latest'));
    expect(text, contains('flutter build macos --config-only'));
    expect(text, contains('xcodebuild test'));
    expect(text, contains('-only-testing:RunnerTests'));
    expect(text, isNot(contains('flutter build macos --debug')));
    expect(centralCi, contains('  build-macos:'));
    expect(centralCi, contains('run: flutter build macos 2>&1 | tee build-macos.log'));
    expect(centralCi, contains('  test:'));
    expect(centralCi, contains('flutter test --coverage --reporter expanded'));
    expect(text, contains('pull_request:'));
    expect(text, isNot(contains('pull_request_target')));
  });

  test(
    'macOS build lane manifest contains no secrets or network requirements',
    () {
      expect(text, contains('permissions:\n  contents: read'));
      expect(text, isNot(contains('secrets.')));
      expect(text, isNot(contains('curl ')));
      expect(text, isNot(contains('wget ')));
    },
  );
}
