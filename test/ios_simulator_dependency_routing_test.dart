import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ac2 simulator dependency changes select feasibility lane', () {
    final text = File('.github/workflows/temp-issue-596.yml')
        .readAsStringSync();
    expect(text, contains('pubspec\\.yaml'));
    expect(text, contains('pubspec\\.lock'));
    expect(text, contains('\\.flutter-version'));
    expect(text, contains('runs-on: macos-latest'));
    expect(text, contains('flutter pub get --enforce-lockfile'));
  });
}
