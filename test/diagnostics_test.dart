import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/diagnostics.dart';

CheckResult _r(String id, CheckStatus status) =>
    CheckResult(id: id, titleEn: id, titleHe: id, status: status);

void main() {
  test('#85: injected fakes report pass/fail/unknown', () async {
    final results = await Diagnostics.run(
      overrides: {
        'a': () async => _r('a', CheckStatus.pass),
        'b': () async => _r('b', CheckStatus.fail),
        'provider': () async => _r('provider', CheckStatus.unknown),
      },
    );
    final byId = {for (final r in results) r.id: r.status};
    expect(byId['a'], CheckStatus.pass);
    expect(byId['b'], CheckStatus.fail);
    expect(byId['provider'], CheckStatus.unknown);
  });

  test('#85: a throwing check reports unknown, never a false pass', () async {
    final results = await Diagnostics.run(
      overrides: {'boom': () async => throw StateError('x')},
    );
    expect(results.every((r) => r.status != CheckStatus.pass), isTrue);
  });

  test('#85: diagnostics report redacts keys', () {
    final report = Diagnostics.buildReport(
      platform: 'macos',
      role: 'host',
      results: [_r('provider', CheckStatus.pass)],
      secretToRedact: 'sk-supersecretvalue123',
    );
    expect(report, contains('provider: pass'));
    expect(report, isNot(contains('sk-supersecretvalue123')));
    expect(
      Diagnostics.buildReport(
        platform: 'macos',
        role: 'host',
        results: [_r('provider', CheckStatus.pass)],
      ),
      isNot(contains(RegExp(r'sk-[A-Za-z0-9]'))),
    );
  });
}
