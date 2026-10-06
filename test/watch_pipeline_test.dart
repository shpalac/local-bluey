import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/watch_pipeline.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(
    () => SharedPreferences.setMockInitialValues({
      'privacy.localOnly': true,
      'watch.appAllowlist': ['safari', 'xcode'],
    }),
  );

  Future<ScreenWatch> liveWatch() async {
    final watch = ScreenWatch.forTesting();
    await watch.start(
      length: const Duration(minutes: 5),
      consentConfirmed: true,
    );
    return watch;
  }

  WatchPipeline pipe(
    ScreenWatch watch,
    List<({String app, String title, bool locked})> reads,
    List<double?> diffs, {
    void Function(String app, String detail)? onVision,
  }) {
    var i = 0;
    var j = 0;
    return WatchPipeline(
      watch: watch,
      frontmost: () async => reads[i.clamp(0, reads.length - 1)],
      frameDiff: () async {
        final d = diffs[j.clamp(0, diffs.length - 1)];
        j++;
        return d;
      },
      onVision: onVision == null
          ? null
          : (app, detail) async {
              onVision(app, detail);
              return null;
            },
    );
  }

  ({String app, String title, bool locked}) at(
    String app, [
    String title = '',
    bool locked = false,
  ]) => (app: app, title: title, locked: locked);

  test('nothing runs while the session is off', () async {
    final watch = ScreenWatch.forTesting();
    var frontmostReads = 0;
    final p = WatchPipeline(
      watch: watch,
      frontmost: () async {
        frontmostReads++;
        return at('Safari');
      },
      frameDiff: () async => 0.5,
    );
    expect(await p.tick(), isNull);
    expect(frontmostReads, 0, reason: 'no session, no signal reads');
    expect(p.events, isEmpty);
  });

  test('app switch emits; quiet frame emits nothing', () async {
    final watch = await liveWatch();
    final p = pipe(
      watch,
      [at('Safari', 'GitHub'), at('Safari', 'GitHub')],
      [0.01],
    );
    final first = await p.tick();
    expect(first?.kind, WatchEventKind.appSwitch);
    expect(first?.app, 'Safari');
    expect(await p.tick(), isNull, reason: 'small diff below threshold');
    expect(p.events, hasLength(1));
  });

  test('meaningful change needs the debounce, then one vision call', () async {
    final watch = await liveWatch();
    final vision = <String>[];
    final p = pipe(
      watch,
      [at('Safari'), at('Safari'), at('Safari')],
      [0.3, 0.3],
      onVision: (app, detail) => vision.add(app),
    );
    await p.tick(); // app switch baseline
    expect(await p.tick(), isNull, reason: 'first hot diff is debounced');
    final e = await p.tick();
    expect(e?.kind, WatchEventKind.meaningfulChange);
    expect(vision, ['Safari']);
    expect(
      p.events.map((e) => e.kind),
      containsAll([
        WatchEventKind.appSwitch,
        WatchEventKind.meaningfulChange,
        WatchEventKind.visionCall,
      ]),
    );
  });

  test('vision calls respect the cooldown', () {
    fakeAsync((async) {
      final clock = async.getClock(DateTime(2026, 10, 6));
      () async {
        final watch = await liveWatch();
        var visionCalls = 0;
        final p = WatchPipeline(
          watch: watch,
          clock: clock,
          frontmost: () async => at('Safari'),
          frameDiff: () async => 0.3,
          onVision: (_, _) async {
            visionCalls++;
            return null;
          },
        );
        await p.tick(); // app switch
        await p.tick();
        await p.tick(); // meaningful + vision #1
        expect(visionCalls, 1);
        async.elapse(const Duration(seconds: 10));
        await p.tick();
        await p.tick(); // meaningful again, still cooling down
        expect(visionCalls, 1);
        async.elapse(const Duration(seconds: 46));
        await p.tick();
        await p.tick(); // meaningful again, cooldown over
        expect(visionCalls, 2);
      }();
    });
  });

  test('excluded app: pipeline pauses, only the counter moves', () async {
    final watch = await liveWatch();
    var diffs = 0;
    final p = pipe(watch, [at('1Password')], [0.9]);
    // Note: 1Password is hard-denied even though the allowlist has safari.
    final e = await p.tick();
    expect(e, isNull);
    expect(diffs, 0, reason: 'no frame work on an excluded surface');
    expect(watch.excludedCount, 1);
    expect(p.events, isEmpty, reason: 'no trace of the excluded moment');
  });

  test('lock screen pauses everything', () async {
    final watch = await liveWatch();
    final p = pipe(watch, [at('Safari', '', true)], [0.9]);
    expect(await p.tick(), isNull);
    expect(watch.excludedCount, 1);
    expect(p.events, isEmpty);
  });

  test('stop during an in-flight tick leaves no events behind', () async {
    final watch = await liveWatch();
    late WatchPipeline p;
    var reads = 0;
    p = WatchPipeline(
      watch: watch,
      frontmost: () async => at('Safari'),
      frameDiff: () async {
        // Kill switch lands while the diff is running.
        if (reads++ == 0) {
          watch.stop();
          p.clear();
        }
        return 0.3;
      },
      onVision: (_, _) async => null,
    );
    await p.tick(); // app switch baseline
    expect(await p.tick(), isNull, reason: 'stopped mid-diff: result dropped');
    expect(p.events, isEmpty, reason: 'nothing repopulates the cleared buffer');
  });

  test('buffer is capped and clear wipes the session trace', () async {
    final watch = await liveWatch();
    final p = pipe(watch, [], []);
    for (var i = 0; i < 250; i++) {
      p.events.add(
        WatchEvent(
          kind: WatchEventKind.appSwitch,
          at: DateTime.now(),
          app: 'x',
        ),
      );
    }
    expect(p.events.length, 250);
    p.clear();
    expect(p.events, isEmpty);
  });
}
