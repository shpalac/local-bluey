import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/benchmark/synthetic_benchmark.dart';

void main() {
  const benchmark = SyntheticBenchmark();
  const positive = SyntheticOutcome.positive;
  const negative = SyntheticOutcome.negative;

  test('deterministic precision, recall and fake elapsed time', () {
    const samples = [
      SyntheticSample(
        id: 'tp',
        expected: positive,
        actual: positive,
        elapsed: Duration(milliseconds: 10),
      ),
      SyntheticSample(
        id: 'fp',
        expected: negative,
        actual: positive,
        elapsed: Duration(milliseconds: 20),
      ),
      SyntheticSample(
        id: 'fn',
        expected: positive,
        actual: negative,
        elapsed: Duration(milliseconds: 30),
      ),
      SyntheticSample(
        id: 'tn',
        expected: negative,
        actual: negative,
        elapsed: Duration(milliseconds: 40),
      ),
    ];
    final first = benchmark.evaluate(samples);
    final second = benchmark.evaluate(samples);
    expect(first.precision, 0.5);
    expect(first.recall, 0.5);
    expect(first.f1, 0.5);
    expect(first.accuracy, 0.5);
    expect(first.meanLatencyMicros, 25000);
    expect(second.totalElapsed, first.totalElapsed);
    expect(second.precision, first.precision);
  });

  test('empty trace has finite zero metrics', () {
    final result = benchmark.evaluate([]);
    expect(result.count, 0);
    expect(result.precision, 0);
    expect(result.recall, 0);
    expect(result.meanLatencyMicros, 0);
  });

  test('rejects duplicate ids and negative durations', () {
    const sample = SyntheticSample(
      id: 'a',
      expected: positive,
      actual: positive,
      elapsed: Duration.zero,
    );
    expect(() => benchmark.evaluate([sample, sample]), throwsArgumentError);
    expect(
      () => benchmark.evaluate([
        const SyntheticSample(
          id: 'a',
          expected: positive,
          actual: positive,
          elapsed: Duration(microseconds: -1),
        ),
      ]),
      throwsArgumentError,
    );
  });
}
