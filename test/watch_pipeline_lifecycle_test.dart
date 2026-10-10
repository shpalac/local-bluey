import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/watch_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<ScreenWatch> live() async {
    final watch = ScreenWatch.forTesting(
      localOnly: () async => true,
      allowlist: () async => ['safari'],
      denylist: () async => [],
    );
    await watch.start(
      length: const Duration(minutes: 5),
      consentConfirmed: true,
    );
    addTearDown(watch.dispose);
    return watch;
  }

  const info = (app: 'Safari', title: 'Document', locked: false);
  for (final stage in ['frontmost', 'diff', 'vision']) {
    for (final dispose in [false, true]) {
      for (final error in [false, true]) {
        test(
          '$stage ${dispose ? "dispose" : "clear"} entered ${error ? "error" : "success"} silent',
          () async {
            final watch = await live();
            final gate = Completer<dynamic>();
            final entered = Completer<void>();
            var hold = false, reads = 0, diffs = 0, visions = 0;
            final p = WatchPipeline(
              watch: watch,
              frontmost: () async {
                reads++;
                if (hold && stage == 'frontmost') {
                  entered.complete();
                  return await gate.future as FrontmostInfo;
                }
                return info;
              },
              frameDiff: () async {
                diffs++;
                if (hold && stage == 'diff') {
                  entered.complete();
                  return await gate.future as double;
                }
                return 0.3;
              },
              onVision: (_, _) async {
                visions++;
                if (hold && stage == 'vision') {
                  entered.complete();
                  return await gate.future as String;
                }
                return 'summary';
              },
            );
            final emitted = <WatchEvent>[];
            final sub = p.stream.listen(emitted.add);
            await p.tick();
            if (stage == 'vision') await p.tick();
            hold = true;
            final pending = p.tick();
            await entered.future;
            expect(
              stage == 'frontmost'
                  ? reads
                  : stage == 'diff'
                  ? diffs
                  : visions,
              greaterThan(0),
            );
            final beforeReads = reads,
                beforeDiffs = diffs,
                beforeVision = visions;
            if (dispose) {
              await p.dispose();
              await p.dispose();
            } else {
              p.clear();
            }
            await Future<void>.delayed(Duration.zero);
            final before = emitted.length;
            if (error) {
              gate.completeError(StateError('stale'));
            } else {
              gate.complete(
                stage == 'frontmost'
                    ? info
                    : stage == 'diff'
                    ? 0.3
                    : 'late summary',
              );
            }
            expect(await pending, isNull);
            await Future<void>.delayed(Duration.zero);
            expect(p.events, isEmpty);
            expect(emitted.length, before);
            if (dispose) {
              expect(await p.tick(), isNull);
              expect(reads, beforeReads);
              expect(diffs, beforeDiffs);
              expect(visions, beforeVision);
            } else {
              hold = false;
              expect((await p.tick())?.kind, WatchEventKind.appSwitch);
              expect(p.events.length, 1);
            }
            await sub.cancel();
            await p.dispose();
          },
        );
      }
    }
  }
  test(
    'stop restart during frontmost never uses old signal for new capture',
    () async {
      final watch = await live();
      final gate = Completer<FrontmostInfo>();
      var diff = 0;
      final p = WatchPipeline(
        watch: watch,
        frontmost: () => gate.future,
        frameDiff: () async {
          diff++;
          return 0.3;
        },
      );
      final pending = p.tick();
      await Future<void>.delayed(Duration.zero);
      watch.stop();
      await watch.start(
        length: const Duration(minutes: 5),
        consentConfirmed: true,
      );
      gate.complete(info);
      expect(await pending, isNull);
      expect(p.events, isEmpty);
      expect(diff, 0);
      await p.dispose();
    },
  );
  test(
    'clear resets baseline debounce and same-clock vision cooldown',
    () async {
      final watch = await live();
      var visions = 0;
      final p = WatchPipeline(
        watch: watch,
        clock: Clock.fixed(DateTime(2026)),
        frontmost: () async => info,
        frameDiff: () async => 0.3,
        onVision: (_, _) async {
          visions++;
          return 'summary';
        },
      );
      await p.tick();
      await p.tick();
      await p.tick();
      expect(visions, 1);
      await p.tick(); // pending streak
      p.clear();
      expect((await p.tick())?.kind, WatchEventKind.appSwitch);
      expect(await p.tick(), isNull);
      expect(visions, 1);
      expect((await p.tick())?.kind, WatchEventKind.meaningfulChange);
      expect(visions, 2);
      await p.dispose();
    },
  );
  test('oversized strings fail silent without prefix baseline or summary retention', () async {
    final watch = await live();
    var title = 'x' * 513;
    var app = 'Safari';
    var visions = 0;
    final p = WatchPipeline(
      watch: watch,
      frontmost: () async => (app: app, title: title, locked: false),
      frameDiff: () async => 0.3,
      onVision: (_, _) async {
        visions++;
        return 's' * 513;
      },
    );
    expect(await p.tick(), isNull);
    expect(p.events, isEmpty);
    title = 'x' * 512;
    expect((await p.tick())?.kind, WatchEventKind.appSwitch);
    await p.tick();
    await p.tick();
    expect(visions, 1);
    expect(p.events.where((e) => e.kind == WatchEventKind.visionCall), isEmpty);
    title = 'x' * 512 + 'y';
    expect(await p.tick(), isNull);
    title = 'x' * 512;
    expect((await p.tick())?.kind, WatchEventKind.appSwitch);
    app = 'a' * 129;
    expect(await p.tick(), isNull);
    expect(
      p.events.every((e) => e.app.length <= 128 && e.detail.length <= 512),
      isTrue,
    );
    await p.dispose();
  });
  test(
    'current source errors still propagate rather than fake quiet success',
    () async {
      final watch = await live();
      final p = WatchPipeline(
        watch: watch,
        frontmost: () async => throw StateError('current'),
        frameDiff: () async => 0.3,
      );
      await expectLater(p.tick(), throwsStateError);
      await p.dispose();
    },
  );
  test(
    'clear while policy gate entered cannot mutate reset baseline',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var hold = false;
      final watch = ScreenWatch.forTesting(
        localOnly: () async {
          if (hold) {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          return true;
        },
        allowlist: () async => ['safari'],
        denylist: () async => [],
      );
      await watch.start(
        length: const Duration(minutes: 5),
        consentConfirmed: true,
      );
      final p = WatchPipeline(
        watch: watch,
        frontmost: () async => info,
        frameDiff: () async => 0.3,
      );
      hold = true;
      final pending = p.tick();
      await entered.future;
      p.clear();
      release.complete();
      expect(await pending, isNull);
      expect(p.events, isEmpty);
      hold = false;
      expect((await p.tick())?.kind, WatchEventKind.appSwitch);
      await p.dispose();
      watch.dispose();
    },
  );
  for (final stage in ['diff', 'vision']) {
    test('current $stage errors remain visible', () async {
      final watch = await live();
      final p = WatchPipeline(
        watch: watch,
        frontmost: () async => info,
        frameDiff: () async {
          if (stage == 'diff') throw StateError('current diff');
          return 0.3;
        },
        onVision: (_, _) async => throw StateError('current vision'),
      );
      await p.tick();
      if (stage == 'vision') await p.tick();
      await expectLater(p.tick(), throwsStateError);
      await p.dispose();
    });
  }
}
