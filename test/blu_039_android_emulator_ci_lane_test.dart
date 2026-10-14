import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BLU-039: structural checks on the existing android-integration lane in
/// .github/workflows/ci.yml. They do not prove emulator runs are stable; that
/// evidence comes from the lane's own CI runs.
void main() {
  final text = File('.github/workflows/ci.yml').readAsStringSync();
  final start = text.indexOf('\n  android-integration:');
  final lane = start < 0 ? '' : text.substring(start);

  test('android emulator ci lane acceptance smoke test', () {
    expect(start, greaterThan(0), reason: 'android-integration job missing');
    expect(lane, contains('reactivecircus/android-emulator-runner@'));
    expect(lane, contains('api-level: \${{ matrix.api-level }}'));
    expect(lane, contains('flutter test integration_test'));
    expect(lane, contains('runs-on: ubuntu-latest'));
  });

  test('android emulator lane is a required aggregate dependency', () {
    final build = RegExp(r'needs: \[detect, [^\]]*android-integration[^\]]*\]');
    expect(build.hasMatch(text), isTrue);
  });
}
