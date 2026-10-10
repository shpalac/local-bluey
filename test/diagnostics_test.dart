import 'dart:io' show ProcessException;

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/diagnostics.dart';

CheckResult _r(String id, CheckStatus status) =>
    CheckResult(id: id, titleEn: id, titleHe: id, status: status);

void main() {
  linuxDepsTests();
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
      isLinux: () => false,
      overrides: {
        'provider': () async => _r('provider', CheckStatus.unknown),
        'boom': () async => throw StateError('x'),
      },
    );
    expect(results.every((r) => r.status != CheckStatus.pass), isTrue);
    expect(
      results.singleWhere((r) => r.id == 'boom').status,
      CheckStatus.unknown,
    );
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

// #152: Linux runtime dependency checks.
void linuxDepsTests() {
  test(
    '#152: on non-Linux the checks report unknown, never a false pass',
    () async {
      final results = await Diagnostics.run(
        isLinux: () => false,
        overrides: {
          'provider': () async => _r('provider', CheckStatus.unknown),
        },
      );
      final linux = results.where((r) => r.id.startsWith('linux_'));
      expect(linux.length, 4);
      expect(linux.every((r) => r.status == CheckStatus.unknown), isTrue);
    },
  );

  test(
    '#152: missing binaries fail with the apt fix, found ones pass',
    () async {
      final results = await Diagnostics.run(
        isLinux: () => true,
        overrides: {
          'provider': () async => _r('provider', CheckStatus.unknown),
        },
        which: (binary) async => binary == 'secret-tool',
      );
      final byId = {for (final r in results) r.id: r};
      expect(byId['linux_keyring']!.status, CheckStatus.pass);
      expect(byId['linux_keyring']!.fixEn, isNull);
      for (final id in ['linux_display', 'linux_discovery', 'linux_audio']) {
        expect(byId[id]!.status, CheckStatus.fail);
        expect(byId[id]!.fixEn, contains('apt install'));
        expect(byId[id]!.fixHe, contains('apt install'));
      }
    },
  );

  test('#152: a lookup error reports unknown, never a false pass', () async {
    final results = await Diagnostics.run(
      isLinux: () => true,
      overrides: {'provider': () async => _r('provider', CheckStatus.unknown)},
      which: (_) async => throw const ProcessException('which', []),
    );
    final linux = results.where((r) => r.id.startsWith('linux_'));
    expect(linux.every((r) => r.status == CheckStatus.unknown), isTrue);
  });

  test(
    '#152: linux checks appear in the redacted diagnostics report',
    () async {
      final results = await Diagnostics.run(
        isLinux: () => false,
        overrides: {
          'provider': () async => _r('provider', CheckStatus.unknown),
        },
      );
      final report = Diagnostics.buildReport(
        platform: 'linux',
        role: 'host',
        results: results,
      );
      expect(report, contains('linux_display: unknown'));
    },
  );
}
