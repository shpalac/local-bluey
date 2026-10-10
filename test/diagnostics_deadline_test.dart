import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/diagnostics.dart';

const ids = [
  'provider',
  'pairing',
  'linux_display',
  'linux_keyring',
  'linux_discovery',
  'linux_audio',
];
CheckResult r(String id, [CheckStatus status = CheckStatus.pass]) =>
    CheckResult(id: id, titleEn: 'fixture', titleHe: 'fixture', status: status);
Map<String, Check> checks() => {for (final id in ids) id: () async => r(id)};
void main() {
  for (final index in [0, 2, 5]) {
    for (final error in [false, true]) {
      test(
        'entered check $index timeout before late ${error ? "error" : "pass"} progresses ordered',
        () {
          fakeAsync((async) {
            final held = Completer<CheckResult>();
            final overrides = checks();
            var entered = false;
            overrides[ids[index]] = () {
              entered = true;
              return held.future;
            };
            List<CheckResult>? result;
            Diagnostics.run(
              overrides: overrides,
              checkTimeout: const Duration(seconds: 2),
            ).then((v) => result = v);
            async.flushMicrotasks();
            expect(entered, isTrue);
            expect(result, isNull);
            async.elapse(const Duration(milliseconds: 1999));
            async.flushMicrotasks();
            expect(result, isNull);
            async.elapse(const Duration(milliseconds: 1));
            async.flushMicrotasks();
            expect(result, isNotNull);
            expect(result!.map((e) => e.id), ids);
            expect(result!.length, 6);
            expect(result![index].status, CheckStatus.unknown);
            expect(
              result!.where((e) => e.status == CheckStatus.pass).length,
              5,
            );
            final saved = List<CheckResult>.of(result!);
            if (error) {
              held.completeError(StateError('private late error'));
            } else {
              held.complete(r(ids[index]));
            }
            async.flushMicrotasks();
            expect(result, saved);
            expect(async.nonPeriodicTimerCount, 0);
          });
        },
      );
    }
  }
  for (final id in ids) {
    test('throw retains built-in EN/HE identity $id', () async {
      final overrides = checks();
      overrides[id] = () => throw StateError('secret detail');
      final results = await Diagnostics.run(overrides: overrides);
      final failed = results.singleWhere((r) => r.id == id);
      expect(failed.status, CheckStatus.unknown);
      expect(failed.titleEn, isNot('fixture'));
      expect(failed.titleHe, isNot('fixture'));
      expect(failed.fixEn, isNull);
      expect(failed.fixHe, isNull);
      expect(results.map((e) => e.id), ids);
      if (id != 'pairing') expect(failed.titleEn, isNot('Phone pairing'));
    });
  }
  test(
    'duplicate/mismatched returned ids cannot impersonate another check',
    () async {
      final overrides = checks();
      overrides['provider'] = () async => r('pairing');
      overrides['linux_display'] = () async => r('pairing');
      final results = await Diagnostics.run(overrides: overrides);
      expect(results.map((r) => r.id), ids);
      expect(results[0].status, CheckStatus.unknown);
      expect(results[2].status, CheckStatus.unknown);
      expect(results[1].status, CheckStatus.pass);
    },
  );
  test('custom failure generic safe metadata and key preserved', () async {
    final results = await Diagnostics.run(
      overrides: {
        ...checks(),
        'custom': () => throw StateError('private'),
        'other': () async => r('pairing'),
      },
    );
    for (final id in ['custom', 'other']) {
      final value = results.singleWhere((r) => r.id == id);
      expect(value.status, CheckStatus.unknown);
      expect(value.titleEn, 'Additional diagnostic check');
      expect(value.titleHe, 'בדיקת אבחון נוספת');
    }
    expect(results.length, 8);
  });
  test(
    'current correct result preserved; timeout positive validation',
    () async {
      final result = await Diagnostics.run(overrides: checks());
      expect(result.every((r) => r.status == CheckStatus.pass), isTrue);
      await expectLater(
        Diagnostics.run(overrides: checks(), checkTimeout: Duration.zero),
        throwsArgumentError,
      );
      await expectLater(
        Diagnostics.run(
          overrides: checks(),
          checkTimeout: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    },
  );
  test('all checks pending complete at one budget each in order', () {
    fakeAsync((async) {
      final pending = {for (final id in ids) id: Completer<CheckResult>()};
      final entered = <String>[];
      List<CheckResult>? result;
      Diagnostics.run(
        checkTimeout: const Duration(seconds: 1),
        overrides: {
          for (final id in ids)
            id: () {
              entered.add(id);
              return pending[id]!.future;
            },
        },
      ).then((v) => result = v);
      async.flushMicrotasks();
      expect(entered, [ids.first]);
      for (var i = 1; i <= ids.length; i++) {
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(entered, ids.take((i + 1).clamp(0, ids.length)).toList());
        if (i < ids.length) expect(result, isNull);
      }
      expect(result!.map((r) => r.id), ids);
      expect(result!.every((r) => r.status == CheckStatus.unknown), isTrue);
      for (final c in pending.values) {
        c.completeError(StateError('late'));
      }
      async.flushMicrotasks();
      expect(async.nonPeriodicTimerCount, 0);
    });
  });
  test('immediate async error is handled before deadline wrapper', () async {
    final overrides = checks();
    overrides['provider'] = () async => throw StateError('async current');
    final results = await Diagnostics.run(overrides: overrides);
    expect(results.first.id, 'provider');
    expect(results.first.status, CheckStatus.unknown);
    expect(results.length, 6);
  });
}
