import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BLU-040: structural checks on the iOS simulator lane definitions. They do
/// not prove simulator runs are stable; that evidence comes from CI runs.
void main() {
  final ci = File('.github/workflows/ci.yml').readAsStringSync();
  final start = ci.indexOf('\n  simulator:');
  final simulator = start < 0 ? '' : ci.substring(start);
  final temp = File('.github/workflows/temp-issue-596.yml').readAsStringSync();

  test('iOS simulator feasibility baseline is deterministic', () {
    expect(start, greaterThan(0), reason: 'simulator job missing in ci.yml');
    expect(simulator, contains('flutter build ios --simulator --debug'));
    expect(simulator, contains('tool/simulator_smoke.sh'));
    expect(File('tool/simulator_smoke.sh').existsSync(), isTrue);
    expect(temp, contains('runs-on: macos-latest'));
    expect(temp, contains('flutter pub get --enforce-lockfile'));
  });

  test('temporary iOS lane has read-only permissions and no secrets', () {
    expect(temp, contains('permissions:\n  contents: read'));
    expect(temp, isNot(contains('secrets.')));
    expect(temp, isNot(contains('pull_request_target')));
    expect(temp, isNot(contains('curl ')));
  });
}
