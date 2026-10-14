import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/benchmark/synthetic_benchmark.dart';
import 'package:local_bluey/benchmark/synthetic_trace_harness.dart';

void main() {
  const positive = SyntheticOutcome.positive;
  const negative = SyntheticOutcome.negative;

  test('fake-clock traces reproduce every synthetic exit path', () {
    final clock = FakeBenchmarkClock();
    final harness = SyntheticTraceHarness(clock);
    for (final exit in SyntheticExit.values) {
      final start = clock.elapsed;
      clock.advance(const Duration(milliseconds: 5));
      harness.record(
        id: exit.name,
        expected: exit == SyntheticExit.success ? positive : negative,
        actual: exit == SyntheticExit.success ? positive : negative,
        exit: exit,
        startedAt: start,
      );
    }
    expect(harness.traces.length, SyntheticExit.values.length);
    expect(harness.metrics().accuracy, 1);
    expect(harness.metrics().meanLatencyMicros, 5000);
    expect(harness.metrics().totalElapsed, const Duration(milliseconds: 35));
  });

  test('duplicate id and clock rollback are rejected without mutation', () {
    final clock = FakeBenchmarkClock();
    final harness = SyntheticTraceHarness(clock);
    expect(
      () => clock.advance(const Duration(microseconds: -1)),
      throwsArgumentError,
    );
    expect(
      () => harness.record(
        id: 'future',
        expected: positive,
        actual: negative,
        exit: SyntheticExit.timeout,
        startedAt: const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
    expect(harness.traces, isEmpty);
    harness.record(
      id: 'future',
      expected: positive,
      actual: negative,
      exit: SyntheticExit.timeout,
      startedAt: Duration.zero,
    );
    expect(
      () => harness.record(
        id: 'future',
        expected: positive,
        actual: positive,
        exit: SyntheticExit.success,
        startedAt: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(harness.traces.length, 1);
  });

  test('trace snapshots are immutable', () {
    final harness = SyntheticTraceHarness(FakeBenchmarkClock());
    expect(
      () => harness.traces.add(
        const SyntheticTrace(
          id: 'no',
          expected: positive,
          actual: negative,
          exit: SyntheticExit.cancelled,
          elapsed: Duration.zero,
        ),
      ),
      throwsUnsupportedError,
    );
  });
}
