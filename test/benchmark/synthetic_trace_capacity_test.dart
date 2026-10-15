import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/benchmark/synthetic_benchmark.dart';
import 'package:local_bluey/benchmark/synthetic_trace_harness.dart';

void main() {
  test('ac2 capacity rejection leaves benchmark trace immutable', () {
    final clock = FakeBenchmarkClock();
    final harness = SyntheticTraceHarness(clock, maxTraces: 1);
    void record(String id) => harness.record(
      id: id,
      expected: SyntheticOutcome.positive,
      actual: SyntheticOutcome.positive,
      exit: SyntheticExit.success,
      startedAt: Duration.zero,
    );

    record('first');
    expect(() => record('second'), throwsStateError);
    expect(harness.traces.single.id, 'first');
    expect(harness.metrics().count, 1);
    expect(harness.metrics().accuracy, 1);
  });

  test('ac3 trace capacity must be finite and positive', () {
    final clock = FakeBenchmarkClock();
    for (final size in [0, -1, 100001]) {
      expect(
        () => SyntheticTraceHarness(clock, maxTraces: size),
        throwsArgumentError,
      );
    }
    final fresh = SyntheticTraceHarness(clock, maxTraces: 2);
    expect(fresh.traces, isEmpty);
  });
}
