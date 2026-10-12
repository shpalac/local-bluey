import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/capture_monitor.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/watch_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'privacy.localOnly': true});
  });

  tearDown(() => PrivacyGuard.debugLocalOnlyOverride = null);

  Future<ScreenWatch> started() async {
    await WatchPolicy.addToAllowlist('Safari');
    final watch = ScreenWatch.forTesting();
    expect(await watch.start(consentConfirmed: true), isNull);
    addTearDown(watch.stop);
    return watch;
  }

  Future<String?> run(CaptureMonitor m, String app, {bool locked = false}) =>
      m.runIfAllowed<String>(
        frontApp: app,
        windowTitle: 'Some title',
        locked: locked,
        operation: () async => 'frame',
      );

  test('fresh state is off and cannot be resumed or paused into life', () {
    final watch = ScreenWatch.forTesting();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    expect(m.indicator, CaptureIndicator.off);
    expect(m.pause(), isFalse);
    expect(m.resume(), isFalse);
    expect(watch.isActive, isFalse);
    expect(m.indicator, CaptureIndicator.off);
  });

  test('indicator follows the session and pause never starts one', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    expect(m.indicator, CaptureIndicator.active);
    expect(m.pause(), isTrue);
    expect(m.indicator, CaptureIndicator.paused);
    expect(m.pause(), isFalse);
    expect(m.resume(), isTrue);
    expect(m.indicator, CaptureIndicator.active);
    m.stop();
    expect(m.indicator, CaptureIndicator.off);
    expect(m.resume(), isFalse);
    expect(watch.isActive, isFalse);
  });

  test('paused observation runs nothing and is counted', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    expect(await run(m, 'Safari'), 'frame');
    m.pause();
    expect(await run(m, 'Safari'), isNull);
    expect(m.refusals[CaptureRefusal.paused], 1);
    m.resume();
    expect(await run(m, 'Safari'), 'frame');
  });

  test('a pause does not survive the session ending', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    m.pause();
    watch.stop();
    expect(m.indicator, CaptureIndicator.off);
    await WatchPolicy.addToAllowlist('Safari');
    expect(await watch.start(consentConfirmed: true), isNull);
    addTearDown(watch.stop);
    expect(
      m.indicator,
      CaptureIndicator.active,
      reason: 'new session, no pause',
    );
    expect(m.paused, isFalse);
  });

  test('policy refusals are counted by reason, with no app names', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    expect(await run(m, '1Password'), isNull);
    expect(await run(m, 'Notes'), isNull);
    expect(await run(m, 'Safari', locked: true), isNull);
    expect(m.refusals[CaptureRefusal.hardDenied], 1);
    expect(m.refusals[CaptureRefusal.notAllowed], 1);
    expect(m.refusals[CaptureRefusal.locked], 1);
    expect(m.refusals[CaptureRefusal.privateWindow], 0);
    expect(m.refusals.toString(), isNot(contains('1Password')));
    m.resetRefusals();
    expect(m.refusals.values.every((v) => v == 0), isTrue);
  });

  test('stop is immediate and an in-flight result is discarded', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    final result = await m.runIfAllowed<String>(
      frontApp: 'Safari',
      operation: () async {
        m.stop();
        return 'late frame';
      },
    );
    expect(result, isNull);
    expect(watch.isActive, isFalse);
  });

  test('locking stops capture; an unlocked change does not', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    final lock = ValueNotifier<bool>(false);
    m.attachLock(lock, () => lock.value);
    lock.value = false;
    expect(watch.isActive, isTrue);
    lock.value = true;
    expect(watch.isActive, isFalse);
    expect(m.indicator, CaptureIndicator.off);
    expect(m.refusals[CaptureRefusal.locked], 1);
  });

  test(
    'attaching while already locked stops, and a throwing check fails closed',
    () async {
      final watch = await started();
      final m = CaptureMonitor(watch: watch);
      addTearDown(m.dispose);
      m.attachLock(ValueNotifier<bool>(true), () => throw StateError('boom'));
      expect(watch.isActive, isFalse);
    },
  );

  test('a fresh monitor after a restart starts off with zero counters', () {
    final m = CaptureMonitor(watch: ScreenWatch.forTesting());
    addTearDown(m.dispose);
    expect(m.indicator, CaptureIndicator.off);
    expect(m.refusals.values.every((v) => v == 0), isTrue);
  });

  test('the monitor notifies listeners on pause, resume and stop', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    var n = 0;
    m.addListener(() => n++);
    m.pause();
    m.resume();
    m.stop();
    expect(n, greaterThanOrEqualTo(2));
  });

  group('lifecycle fences', () {
    Completer<void>? hold;
    Future<List<String>> heldAllowlist() async {
      final h = hold;
      if (h != null) await h.future;
      return ['safari'];
    }

    Future<ScreenWatch> heldWatch() async {
      hold = null;
      final watch = ScreenWatch.forTesting(allowlist: heldAllowlist);
      expect(await watch.start(consentConfirmed: true), isNull);
      addTearDown(watch.stop);
      return watch;
    }

    test('external start and stop notify exactly once each', () async {
      final watch = ScreenWatch.forTesting();
      await WatchPolicy.addToAllowlist('Safari');
      final m = CaptureMonitor(watch: watch);
      addTearDown(m.dispose);
      var n = 0;
      m.addListener(() => n++);
      expect(await watch.start(consentConfirmed: true), isNull);
      expect(n, 1);
      expect(m.indicator, CaptureIndicator.active);
      watch.stop();
      expect(n, 2);
      expect(m.indicator, CaptureIndicator.off);
      // Paused session ended from outside: one notification, pause forgotten.
      expect(await watch.start(consentConfirmed: true), isNull);
      expect(n, 3);
      expect(m.pause(), isTrue);
      expect(n, 4);
      watch.stop();
      expect(n, 5);
      expect(m.paused, isFalse);
      expect(m.indicator, CaptureIndicator.off);
    });

    test('exact notifications for pause, resume and stop', () async {
      final watch = await started();
      final m = CaptureMonitor(watch: watch);
      addTearDown(m.dispose);
      var n = 0;
      m.addListener(() => n++);
      m.pause();
      expect(n, 1);
      m.resume();
      expect(n, 2);
      m.stop();
      expect(n, 3);
    });

    test('dispose during the gate: the operation never runs', () async {
      final watch = await heldWatch();
      final m = CaptureMonitor(watch: watch);
      hold = Completer<void>();
      var ran = false;
      final f = m.runIfAllowed<String>(
        frontApp: 'Safari',
        operation: () async {
          ran = true;
          return 'frame';
        },
      );
      m.dispose();
      hold!.complete();
      expect(await f, isNull);
      expect(ran, isFalse);
    });

    test(
      'stop and restart between the gates: the old request is refused',
      () async {
        final watch = await heldWatch();
        final m = CaptureMonitor(watch: watch);
        addTearDown(m.dispose);
        hold = Completer<void>();
        var ran = false;
        final f = m.runIfAllowed<String>(
          frontApp: 'Safari',
          operation: () async {
            ran = true;
            return 'old session frame';
          },
        );
        watch.stop();
        hold!.complete();
        hold = null;
        expect(await watch.start(consentConfirmed: true), isNull);
        expect(await f, isNull);
        expect(ran, isFalse);
        // A new request in the new session works.
        expect(await run(m, 'Safari'), 'frame');
      },
    );

    test(
      'pause then resume during a held gate still refuses that request',
      () async {
        final watch = await heldWatch();
        final m = CaptureMonitor(watch: watch);
        addTearDown(m.dispose);
        hold = Completer<void>();
        var ran = false;
        final f = m.runIfAllowed<String>(
          frontApp: 'Safari',
          operation: () async {
            ran = true;
            return 'frame';
          },
        );
        m.pause();
        m.resume();
        hold!.complete();
        expect(await f, isNull);
        expect(ran, isFalse);
      },
    );

    test('pause during an entered operation drops its result', () async {
      final watch = await started();
      final m = CaptureMonitor(watch: watch);
      addTearDown(m.dispose);
      final r = await m.runIfAllowed<String>(
        frontApp: 'Safari',
        operation: () async {
          m.pause();
          return 'frame taken while pausing';
        },
      );
      expect(r, isNull);
      expect(m.paused, isTrue);
      expect(await run(m, 'Safari'), isNull);
    });

    test('lifecycle calls after dispose are safe and attach nothing', () async {
      final watch = await started();
      final m = CaptureMonitor(watch: watch);
      m.pause();
      expect(await run(m, 'Safari'), isNull);
      expect(m.refusals[CaptureRefusal.paused], 1);
      m.dispose();
      final lock = ValueNotifier<bool>(true);
      m.attachLock(lock, () => lock.value);
      lock.value = false;
      lock.value = true;
      expect(watch.isActive, isTrue);
      m.resetRefusals();
      // resetRefusals is a no-op after dispose: the count is untouched.
      expect(m.refusals[CaptureRefusal.paused], 1);
      expect(await run(m, 'Safari'), isNull);
      // Stopping stays effective after dispose (safe direction).
      m.stop();
      expect(watch.isActive, isFalse);
    });

    // A controlled hold on the SECOND allowlist ask: the monitor's own gate
    // (first ask) passes, then ScreenWatch.runIfAllowed's gate (second ask)
    // is held while the session changes.
    Future<(ScreenWatch, Completer<void>, void Function())>
    secondAskHeld() async {
      var calls = 0;
      var armed = false;
      final gate = Completer<void>();
      final watch = ScreenWatch.forTesting(
        allowlist: () async {
          if (armed && ++calls == 2) await gate.future;
          return ['safari'];
        },
      );
      expect(await watch.start(consentConfirmed: true), isNull);
      addTearDown(watch.stop);
      return (watch, gate, () => armed = true);
    }

    test('second ask held, pause+resume: operation does not enter', () async {
      final (watch, gate, arm) = await secondAskHeld();
      final m = CaptureMonitor(watch: watch);
      addTearDown(m.dispose);
      arm();
      var ran = false;
      final f = m.runIfAllowed<String>(
        frontApp: 'Safari',
        operation: () async {
          ran = true;
          return 'frame';
        },
      );
      await Future<void>.delayed(Duration.zero);
      m.pause();
      m.resume();
      gate.complete();
      expect(await f, isNull);
      expect(ran, isFalse);
    });

    test('second ask held, stop+restart: operation does not enter', () async {
      final (watch, gate, arm) = await secondAskHeld();
      final m = CaptureMonitor(watch: watch);
      addTearDown(m.dispose);
      arm();
      var ran = false;
      final f = m.runIfAllowed<String>(
        frontApp: 'Safari',
        operation: () async {
          ran = true;
          return 'old frame';
        },
      );
      await Future<void>.delayed(Duration.zero);
      watch.stop();
      expect(await watch.start(consentConfirmed: true), isNull);
      gate.complete();
      expect(await f, isNull);
      expect(ran, isFalse);
    });

    test('second ask held, dispose: operation does not enter', () async {
      final (watch, gate, arm) = await secondAskHeld();
      final m = CaptureMonitor(watch: watch);
      arm();
      var ran = false;
      final f = m.runIfAllowed<String>(
        frontApp: 'Safari',
        operation: () async {
          ran = true;
          return 'frame';
        },
      );
      await Future<void>.delayed(Duration.zero);
      m.dispose();
      gate.complete();
      expect(await f, isNull);
      expect(ran, isFalse);
    });

    test('expiry by the session timer notifies once and shows off', () {
      fakeAsync((zone) {
        // ignore: avoid_async_calls_in_sync_code - fakeAsync drives the clock.
        Zone.current.run(() async {
          final watch = await started();
          final m = CaptureMonitor(watch: watch);
          var n = 0;
          m.addListener(() => n++);
          expect(m.indicator, CaptureIndicator.active);
          zone.elapse(const Duration(minutes: 4));
          expect(n, 0, reason: 'ticks alone do not change the indicator');
          zone.elapse(const Duration(minutes: 1, seconds: 2));
          expect(watch.isActive, isFalse);
          expect(m.indicator, CaptureIndicator.off);
          expect(n, 1);
          m.dispose();
        });
        zone.flushMicrotasks();
      });
    });

    test(
      'a policy change during the gate refuses and counts notAllowed',
      () async {
        final watch = await heldWatch();
        final m = CaptureMonitor(watch: watch);
        addTearDown(m.dispose);
        var calls = 0;
        var ran = false;
        // Allowlist is fine for the first ask, then the user removes the app.
        final w2 = ScreenWatch.forTesting(
          allowlist: () async => calls++ < 2 ? ['safari'] : <String>[],
        );
        expect(await w2.start(consentConfirmed: true), isNull);
        addTearDown(w2.stop);
        final m2 = CaptureMonitor(watch: w2);
        addTearDown(m2.dispose);
        final r = await m2.runIfAllowed<String>(
          frontApp: 'Safari',
          operation: () async {
            ran = true;
            return 'frame';
          },
        );
        expect(r, isNull);
        expect(ran, isFalse);
        expect(m2.refusals[CaptureRefusal.notAllowed], greaterThanOrEqualTo(1));
      },
    );

    test('private window in front is refused and counted', () async {
      final watch = await started();
      final m = CaptureMonitor(watch: watch);
      addTearDown(m.dispose);
      final r = await m.runIfAllowed<String>(
        frontApp: 'Safari',
        windowTitle: 'Private Browsing',
        operation: () async => 'frame',
      );
      expect(r, isNull);
      expect(m.refusals[CaptureRefusal.privateWindow], 1);
    });
  });
}
