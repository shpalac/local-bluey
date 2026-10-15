import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/diagnostics.dart';

void main() {
  test('AC-1 diagnostics report never includes untrusted metadata', () {
    final secret = ['sk-', 'fixture-', 'fixture-', 'fixture-', '0000'].join();
    final report = Diagnostics.buildReport(
      platform: 'macos\nAuthorization: Bearer $secret',
      role: 'host\nScreenshot: /Users/alice/Desktop/screen.png',
      results: const [
        CheckResult(
          id: 'provider',
          titleEn: 'Email alice@example.com',
          titleHe: 'private',
          status: CheckStatus.unknown,
          fixEn: 'Never export this private message',
        ),
      ],
    );

    expect(report, contains('Platform: unknown'));
    expect(report, contains('Role: unknown'));
    expect(report, contains('provider: unknown'));
    expect(report, isNot(contains(secret)));
    expect(report, isNot(contains('alice@example.com')));
    expect(report, isNot(contains('Screenshot:')));
    expect(report, isNot(contains('/Users/alice')));
    expect(report, isNot(contains('Never export')));
  });

  test('diagnostics report retains safe platform and role identifiers', () {
    final report = Diagnostics.buildReport(
      platform: 'macos_15',
      role: 'desktop-host',
      results: const [],
    );

    expect(report, contains('Platform: macos_15'));
    expect(report, contains('Role: desktop-host'));
  });

  test('diagnostics report rejects oversized metadata labels', () {
    final report = Diagnostics.buildReport(
      platform: 'a' * 10000,
      role: 'b' * 10000,
      results: const [],
    );

    expect(report, contains('Platform: unknown'));
    expect(report, contains('Role: unknown'));
    expect(report.length, lessThan(256));
  });
}
