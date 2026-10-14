/// Pure, deterministic synthetic classification benchmark. No IO or device access.
library;

enum SyntheticOutcome { positive, negative }

class SyntheticSample {
  const SyntheticSample({
    required this.id,
    required this.expected,
    required this.actual,
    required this.elapsed,
  });

  final String id;
  final SyntheticOutcome expected;
  final SyntheticOutcome actual;
  final Duration elapsed;
}

class SyntheticMetrics {
  const SyntheticMetrics({
    required this.truePositive,
    required this.falsePositive,
    required this.falseNegative,
    required this.trueNegative,
    required this.totalElapsed,
  });

  final int truePositive;
  final int falsePositive;
  final int falseNegative;
  final int trueNegative;
  final Duration totalElapsed;

  int get count => truePositive + falsePositive + falseNegative + trueNegative;
  double get precision => _ratio(truePositive, truePositive + falsePositive);
  double get recall => _ratio(truePositive, truePositive + falseNegative);
  double get accuracy => _ratio(truePositive + trueNegative, count);
  double get f1 => _ratio(
    2 * truePositive,
    2 * truePositive + falsePositive + falseNegative,
  );
  double get meanLatencyMicros => _ratio(totalElapsed.inMicroseconds, count);

  static double _ratio(int numerator, int denominator) =>
      denominator == 0 ? 0 : numerator / denominator;
}

class SyntheticBenchmark {
  const SyntheticBenchmark();

  SyntheticMetrics evaluate(Iterable<SyntheticSample> samples) {
    var tp = 0, fp = 0, fn = 0, tn = 0, micros = 0;
    final ids = <String>{};
    for (final sample in samples) {
      if (sample.id.trim().isEmpty || !ids.add(sample.id)) {
        throw ArgumentError.value(
          sample.id,
          'id',
          'Must be nonempty and unique',
        );
      }
      if (sample.elapsed.isNegative) {
        throw ArgumentError.value(
          sample.elapsed,
          'elapsed',
          'Cannot be negative',
        );
      }
      micros += sample.elapsed.inMicroseconds;
      if (sample.expected == SyntheticOutcome.positive) {
        if (sample.actual == SyntheticOutcome.positive) {
          tp++;
        } else {
          fn++;
        }
      } else if (sample.actual == SyntheticOutcome.positive) {
        fp++;
      } else {
        tn++;
      }
    }
    return SyntheticMetrics(
      truePositive: tp,
      falsePositive: fp,
      falseNegative: fn,
      trueNegative: tn,
      totalElapsed: Duration(microseconds: micros),
    );
  }
}
