import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/screen_watch.dart';

void main() {
  // Bounded sequence model, no capture/provider/store/platform calls.
  for (final sequence in [
    ['deny', 'start', 'duplicate', 'stop', 'start', 'stop'],
    ['start', 'expire', 'deny', 'start', 'stop'],
    ['stop', 'start', 'stop', 'stop', 'start', 'expire'],
  ]) {
    test('session model ${sequence.join('/')}', () async {
      var now = DateTime.utc(2026, 10, 12);
      final watch = ScreenWatch.forTesting(
        clock: Clock(() => now),
        localOnly: () async => true,
        allowlist: () async => ['Notes'],
        denylist: () async => [],
      );
      addTearDown(watch.dispose);
      var active = false;
      for (final action in sequence) {
        switch (action) {
          case 'start':
            expect(await watch.start(consentConfirmed: true), isNull);
            active = true;
          case 'deny':
            expect(await watch.start(consentConfirmed: false), isNotNull);
          case 'duplicate':
            expect(await watch.start(consentConfirmed: true), isNotNull);
          case 'stop':
            watch.stop();
            active = false;
          case 'expire':
            now = now.add(const Duration(minutes: 6));
            await watch.mayObserve(frontApp: 'Notes');
            active = false;
        }
        expect(watch.isActive, active, reason: action);
        expect(watch.remaining > Duration.zero, active, reason: action);
      }
    });
  }
  test(
    'old entered result cannot publish after stop and new session',
    () async {
      final watch = ScreenWatch.forTesting(
        localOnly: () async => true,
        allowlist: () async => ['Notes'],
        denylist: () async => [],
      );
      addTearDown(watch.dispose);
      expect(await watch.start(consentConfirmed: true), isNull);
      final entered = Completer<void>(), release = Completer<String>();
      final old = watch.runIfAllowed(
        frontApp: 'Notes',
        operation: () {
          entered.complete();
          return release.future;
        },
      );
      await entered.future;
      final generation = watch.generation;
      watch.stop();
      expect(watch.generation, greaterThan(generation));
      expect(await watch.start(consentConfirmed: true), isNull);
      release.complete('fabricated stale result');
      expect(await old, isNull);
      expect(watch.isActive, isTrue);
      expect(
        await watch.runIfAllowed(
          frontApp: 'Notes',
          operation: () async => 'current',
        ),
        'current',
      );
    },
  );
  test(
    'policy read failure during active session stops without operation',
    () async {
      var fail = false, calls = 0;
      final watch = ScreenWatch.forTesting(
        localOnly: () async => true,
        allowlist: () async {
          if (fail) throw StateError('fabricated');
          return ['Notes'];
        },
        denylist: () async => [],
      );
      addTearDown(watch.dispose);
      expect(await watch.start(consentConfirmed: true), isNull);
      fail = true;
      expect(
        await watch.runIfAllowed(
          frontApp: 'Notes',
          operation: () async {
            calls++;
            return 'unexpected';
          },
        ),
        isNull,
      );
      expect(calls, 0);
      expect(watch.isActive, isFalse);
      fail = false;
      expect(await watch.start(consentConfirmed: false), isNotNull);
      expect(watch.isActive, isFalse);
    },
  );
}
