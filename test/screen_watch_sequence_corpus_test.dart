import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/screen_watch.dart';

void main() {
  const actions = ['start', 'stop', 'expire', 'deny', 'invalid'];
  test('all 125 three-action sequences match bounded session model', () async {
    for (final a in actions) {
      for (final b in actions) {
        for (final c in actions) {
          var now = DateTime.utc(2026, 10, 12);
          final watch = ScreenWatch.forTesting(
            clock: Clock(() => now),
            localOnly: () async => true,
            allowlist: () async => ['Notes'],
            denylist: () async => [],
          );
          var active = false;
          try {
            for (final action in [a, b, c]) {
              switch (action) {
                case 'start':
                  final result = await watch.start(consentConfirmed: true);
                  expect(result == null, !active);
                  active = true;
                case 'stop':
                  watch.stop();
                  active = false;
                case 'expire':
                  now = now.add(const Duration(minutes: 6));
                  await watch.mayObserve(frontApp: 'Notes');
                  active = false;
                case 'deny':
                  expect(await watch.start(consentConfirmed: false), isNotNull);
                case 'invalid':
                  expect(
                    await watch.start(
                      consentConfirmed: true,
                      length: Duration.zero,
                    ),
                    isNotNull,
                  );
              }
              expect(watch.isActive, active, reason: '$a/$b/$c after $action');
            }
          } finally {
            watch.dispose();
          }
        }
      }
    }
  });
  test(
    'reconstruction never inherits disposed consent or session counters',
    () async {
      ScreenWatch fresh() => ScreenWatch.forTesting(
        localOnly: () async => true,
        allowlist: () async => ['Notes'],
        denylist: () async => [],
      );
      final old = fresh();
      expect(await old.start(consentConfirmed: true), isNull);
      var cancelled = 0;
      old.registerInFlight(() => cancelled++);
      old.dispose();
      expect(cancelled, 1);
      expect(await old.start(consentConfirmed: true), isNotNull);
      final next = fresh();
      addTearDown(next.dispose);
      expect(next.isActive, isFalse);
      expect(next.excludedCount, 0);
      expect(next.generation, 0);
      expect(await next.start(consentConfirmed: false), isNotNull);
      expect(next.isActive, isFalse);
    },
  );
}
