import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/frame_differ.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/watch_driver.dart';
import 'package:local_bluey/services/watch_pipeline.dart';

class HookWatch implements ScreenWatch {
  final hooks = <void Function()>[];
  @override
  bool get isActive => true;
  @override
  void registerInFlight(void Function() cancel) {
    hooks.add(cancel);
  }

  @override
  void unregisterInFlight(void Function() cancel) {
    hooks.remove(cancel);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'run lifetime keeps exactly one cancel hook and removes on manual stop',
    () {
      fakeAsync((zone) {
        final watch = HookWatch();
        final pipeline = WatchPipeline(
          watch: watch,
          frontmost: () async => (app: 'Safari', title: '', locked: false),
          frameDiff: () async => 0,
        );
        final driver = WatchDriver(
          watch: watch,
          pipeline: pipeline,
          differ: FrameDiffer(),
          tick: () async => null,
        );
        for (var i = 0; i < 30; i++) {
          driver.start();
          driver.start();
          expect(watch.hooks.length, 1);
          driver.stop();
          expect(watch.hooks, isEmpty);
        }
        driver.start();
        expect(watch.hooks.length, 1);
        watch.hooks.single();
        expect(driver.running, isFalse);
        expect(watch.hooks, isEmpty);
        pipeline.dispose();
        zone.flushMicrotasks();
      });
    },
  );

  for (final error in [false, true]) {
    for (final restart in [false, true]) {
      test(
        'entered tick stop${restart ? '/restart' : ''} late ${error ? 'error' : 'result'} no resurrection/overlap',
        () {
          fakeAsync((zone) {
            final watch = ScreenWatch.forTesting(
              localOnly: () async => true,
              allowlist: () async => ['safari'],
              denylist: () async => [],
            );
            var ready = false;
            watch.start(consentConfirmed: true).then((_) => ready = true);
            zone.flushMicrotasks();
            expect(ready, isTrue);
            final pipeline = WatchPipeline(
              watch: watch,
              frontmost: () async => (app: 'Safari', title: '', locked: false),
              frameDiff: () async => 0,
            );
            final entered = Completer<WatchEvent?>();
            var reads = 0, active = 0, maxActive = 0;
            final driver = WatchDriver(
              watch: watch,
              pipeline: pipeline,
              differ: FrameDiffer(),
              tick: () async {
                reads++;
                active++;
                if (active > maxActive) maxActive = active;
                try {
                  return reads == 1 ? await entered.future : null;
                } finally {
                  active--;
                }
              },
            );
            driver.start();
            zone.elapse(const Duration(seconds: 1));
            expect(reads, 1);
            expect(driver.running, isTrue);
            driver.stop();
            expect(watch.isActive, isTrue);
            if (restart) driver.start();
            zone.elapse(const Duration(seconds: 10));
            expect(reads, 1);
            if (error) {
              entered.completeError(StateError('old'));
            } else {
              entered.complete(null);
            }
            zone.flushMicrotasks();
            expect(driver.interval, WatchDriver.minInterval);
            zone.elapse(const Duration(milliseconds: 999));
            expect(reads, 1);
            zone.elapse(const Duration(milliseconds: 1));
            expect(reads, restart ? 2 : 1);
            expect(maxActive, 1);
            driver.stop();
            watch.dispose();
            pipeline.dispose();
            zone.flushMicrotasks();
          });
        },
      );
    }
  }
  test('current tick error stops honestly, explicit restart works', () {
    fakeAsync((zone) {
      final watch = ScreenWatch.forTesting(
        localOnly: () async => true,
        allowlist: () async => ['safari'],
        denylist: () async => [],
      );
      watch.start(consentConfirmed: true);
      zone.flushMicrotasks();
      final pipeline = WatchPipeline(
        watch: watch,
        frontmost: () async => (app: 'Safari', title: '', locked: false),
        frameDiff: () async => 0,
      );
      var reads = 0;
      final driver = WatchDriver(
        watch: watch,
        pipeline: pipeline,
        differ: FrameDiffer(),
        tick: () async {
          reads++;
          if (reads == 1) throw StateError('tick');
          return null;
        },
      );
      driver.start();
      zone.elapse(const Duration(seconds: 1));
      expect(reads, 1);
      expect(driver.running, isFalse);
      zone.elapse(const Duration(seconds: 30));
      expect(reads, 1);
      driver.start();
      zone.elapse(const Duration(seconds: 1));
      expect(reads, 2);
      expect(driver.running, isTrue);
      driver.stop();
      watch.dispose();
      pipeline.dispose();
      zone.flushMicrotasks();
    });
  });
  test('quiet bounded backoff and activity returns min; repeated start/stop cancels one hook', () {
    fakeAsync((zone) {
      final watch = ScreenWatch.forTesting(
        localOnly: () async => true,
        allowlist: () async => ['safari'],
        denylist: () async => [],
      );
      watch.start(consentConfirmed: true);
      zone.flushMicrotasks();
      final pipeline = WatchPipeline(
        watch: watch,
        frontmost: () async => (app: 'Safari', title: '', locked: false),
        frameDiff: () async => 0,
      );
      var reads = 0, meaningful = false;
      final driver = WatchDriver(
        watch: watch,
        pipeline: pipeline,
        differ: FrameDiffer(),
        tick: () async {
          reads++;
          return meaningful
              ? WatchEvent(
                  kind: WatchEventKind.meaningfulChange,
                  at: DateTime(2026),
                  app: 'Safari',
                )
              : null;
        },
      );
      for (var i = 0; i < 20; i++) {
        driver.start();
        driver.start();
        driver.stop();
      }
      driver.start();
      zone.elapse(const Duration(seconds: 30));
      expect(driver.interval, WatchDriver.maxInterval);
      meaningful = true;
      zone.elapse(WatchDriver.maxInterval);
      expect(driver.interval, WatchDriver.minInterval);
      final atStop = reads;
      watch.stop();
      expect(driver.running, isFalse);
      zone.elapse(const Duration(seconds: 20));
      expect(reads, atStop);
      expect(pipeline.events, isEmpty);
      pipeline.dispose();
      watch.dispose();
      zone.flushMicrotasks();
    });
  });
}
