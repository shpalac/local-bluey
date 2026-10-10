import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/watch_pipeline.dart';
import 'package:local_bluey/services/watch_suggestions.dart';

WatchEvent event(String app, String detail) => WatchEvent(
  kind: WatchEventKind.visionCall,
  at: DateTime(2026, 10, 10),
  app: app,
  detail: detail,
);
void main() {
  for (final disposal in [false, true]) {
    test(
      'late preference error after invalidation stays silent $disposal',
      () async {
        final read = Completer<Set<String>>();
        final s = WatchSuggestions(readNeverApps: () => read.future);
        final old = s.onEvent(event('Terminal', 'error'));
        if (disposal) {
          await s.dispose();
        } else {
          s.resetSession();
        }
        read.completeError(StateError('late read'));
        expect(await old, isNull);
        expect(s.retainedKeyCount, 0);
        await s.dispose();
      },
    );
  }
  test('oversized app and empty detail do not retain keys', () async {
    final s = WatchSuggestions(readNeverApps: () async => {});
    expect(
      await s.onEvent(
        event('x' * (WatchSuggestions.maxAppLength + 1), 'detail'),
      ),
      isNull,
    );
    expect(await s.onEvent(event('Terminal', '  ')), isNull);
    expect(s.retainedKeyCount, 0);
    await s.dispose();
  });

  for (final disposal in [false, true]) {
    test(
      'entered read stays silent after ${disposal ? 'dispose' : 'reset'}; current events independent',
      () async {
        final read = Completer<Set<String>>();
        var blocked = true;
        final s = WatchSuggestions(
          readNeverApps: () => blocked ? read.future : Future.value({}),
        );
        final emitted = <WatchSuggestion>[];
        final subscription = s.stream.listen(emitted.add);
        final old = s.onEvent(event('Terminal', 'same'));
        if (disposal) {
          s.dispose();
        } else {
          s.resetSession();
        }
        blocked = false;
        read.complete({});
        expect(await old, isNull);
        expect(s.retainedKeyCount, 0);
        for (var i = 0; i < 2; i++) {
          expect(await s.onEvent(event('Terminal', 'same')), isNull);
        }
        final third = await s.onEvent(event('Terminal', 'same'));
        expect(third, disposal ? isNull : isNotNull);
        await Future<void>.delayed(Duration.zero);
        expect(emitted.length, disposal ? 0 : 1);
        await subscription.cancel();
        await s.dispose();
        await s.dispose();
        s.resetSession();
        expect(await s.onEvent(event('Terminal', 'post disposal')), isNull);
      },
    );
  }
  test(
    'same text across apps cannot aggregate; normalized same-app repeat works',
    () async {
      final s = WatchSuggestions(readNeverApps: () async => {});
      expect(await s.onEvent(event('Terminal', 'same')), isNull);
      expect(await s.onEvent(event('Terminal', 'same')), isNull);
      expect(await s.onEvent(event('Safari', 'same')), isNull);
      expect(await s.onEvent(event(' Terminal.app ', ' SAME ')), isNotNull);
      await s.dispose();
    },
  );
  test(
    'unique details bounded FIFO; evicted keys need three fresh repeats',
    () async {
      final s = WatchSuggestions(readNeverApps: () async => {});
      for (var i = 0; i < WatchSuggestions.maxRepeatedKeys + 10; i++) {
        expect(await s.onEvent(event('Terminal', 'detail-$i')), isNull);
        expect(
          s.retainedKeyCount,
          lessThanOrEqualTo(WatchSuggestions.maxRepeatedKeys),
        );
      }
      expect(await s.onEvent(event('Terminal', 'detail-0')), isNull);
      expect(await s.onEvent(event('Terminal', 'detail-0')), isNull);
      expect(await s.onEvent(event('Terminal', 'detail-0')), isNotNull);
      await s.dispose();
      expect(s.retainedKeyCount, 0);
    },
  );
  test(
    'oversized detail stays silent without prefix-collision counting',
    () async {
      final s = WatchSuggestions(readNeverApps: () async => {});
      final prefix = 'x' * WatchSuggestions.maxDetailLength;
      for (var i = 0; i < 20; i++) {
        expect(await s.onEvent(event('Terminal', '$prefix$i')), isNull);
      }
      expect(s.retainedKeyCount, 0);
      for (var i = 0; i < 2; i++) {
        expect(await s.onEvent(event('Terminal', prefix)), isNull);
      }
      final out = await s.onEvent(event('Terminal', prefix));
      expect(out, isNotNull);
      expect(out!.evidence.length, lessThan(600));
      await s.dispose();
    },
  );
  test('concurrent reads obey minGap and session cap', () {
    fakeAsync((zone) {
      final read = Completer<Set<String>>();
      final s = WatchSuggestions(
        clock: zone.getClock(DateTime(2026, 10, 10)),
        readNeverApps: () => read.future,
      );
      var outputs = 0, completed = 0;
      void fire(int round) {
        for (var i = 0; i < 9; i++) {
          s.onEvent(event('Terminal', 'repeat-$round')).then((v) {
            completed++;
            if (v != null) outputs++;
          });
        }
        zone.flushMicrotasks();
      }

      fire(0);
      expect(completed, 0);
      read.complete({});
      zone.flushMicrotasks();
      expect(outputs, 1);
      expect(completed, 9);
      fire(1);
      expect(outputs, 1);
      zone.elapse(WatchSuggestions.minGap);
      fire(2);
      expect(outputs, 2);
      zone.elapse(WatchSuggestions.minGap);
      fire(3);
      expect(outputs, 3);
      zone.elapse(WatchSuggestions.minGap);
      fire(4);
      expect(outputs, 3);
      expect(completed, 45);
      s.dispose();
      zone.flushMicrotasks();
    });
  });
  test(
    'never preference matching normalized; uncertain context skipped',
    () async {
      var reads = 0;
      final s = WatchSuggestions(
        readNeverApps: () async {
          reads++;
          return {' TERMINAL.app '};
        },
      );
      for (var i = 0; i < 3; i++) {
        expect(await s.onEvent(event('Terminal', 'same')), isNull);
      }
      expect(s.retainedKeyCount, 0);
      expect(reads, 3);
      expect(await s.onEvent(event('Unknown', 'same')), isNull);
      expect(reads, 3);
      await s.dispose();
    },
  );
}
