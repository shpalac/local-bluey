import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BLU-038: structural checks on the macOS native build lane workflow file.
/// They do not prove the lane builds on a macOS runner; that evidence comes
/// from the lane's own CI run.
void main() {
  final text = File('.github/workflows/macos-native-build-lane.yml')
      .readAsStringSync();

  test('macOS build lane manifest is deterministic', () {
    expect(text, contains('runs-on: macos-latest'));
    expect(text, contains('flutter build macos --debug'));
    expect(
      text,
      contains('flutter test test/macos_build_lane_manifest_test.dart'),
    );
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
