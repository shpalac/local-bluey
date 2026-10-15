import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ac2 macOS native dependencies and tests rerun the hosted lane', () {
    final workflow = File('.github/workflows/macos-native-build-lane.yml')
        .readAsStringSync();
    for (final path in [
      "      - 'macos/**'",
      "      - 'ios/**'",
      "      - 'lib/**'",
      "      - 'test/macos*'",
      "      - 'pubspec.yaml'",
      "      - 'pubspec.lock'",
      "      - '.flutter-version'",
    ]) {
      expect(workflow, contains(path));
    }
    expect(workflow, contains('runs-on: macos-latest'));
    expect(workflow, contains('CODE_SIGNING_ALLOWED=NO'));
    expect(workflow, contains('permissions:\n  contents: read'));
  });
}
