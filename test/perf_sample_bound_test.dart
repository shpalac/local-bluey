import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/perf_monitor.dart';

void main() {
  test('positive fixture sample bound required', () {
    for (final cap in [0, -1]) {
      expect(
        () => PerfMonitor.forTest(
          file: () async => File('unused'),
          maxRetainedSamplesPerStage: cap,
        ),
        throwsArgumentError,
      );
    }
  });
  test(
    'repeated fabricated durations keep latest window and append all samples',
    () async {
      var now = DateTime.utc(2026, 10, 12);
      var writes = 0;
      final monitor = PerfMonitor.forTest(
        file: () async => File('unused'),
        clock: () => now,
        appendLine: (_, _) async => writes++,
        maxRetainedSamplesPerStage: 3,
      );
      for (var i = 0; i < 200; i++) {
        final result = await monitor.measure('synthetic', () async {
          now = now.add(Duration(milliseconds: i));
          return i;
        });
        expect(result, i);
        expect(monitor.retainedSampleCount('synthetic'), lessThanOrEqualTo(3));
      }
      await monitor.flush();
      expect(writes, 200);
      expect(monitor.retainedSampleCount('synthetic'), 3);
      expect(monitor.medians()['synthetic'], 198);
    },
  );
  test(
    'default recent window is explicit and does not change short history',
    () async {
      var now = DateTime.utc(2026, 10, 12);
      final monitor = PerfMonitor.forTest(
        file: () async => File('unused'),
        clock: () => now,
        appendLine: (_, _) async {},
      );
      for (var i = 0; i < 10; i++) {
        await monitor.measure('synthetic', () async {
          now = now.add(Duration(milliseconds: i));
        });
      }
      await monitor.flush();
      expect(monitor.maxRetainedSamplesPerStage, 1024);
      expect(monitor.retainedSampleCount('synthetic'), 10);
      expect(monitor.medians()['synthetic'], 5);
    },
  );
}
