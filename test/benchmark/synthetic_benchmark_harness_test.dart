import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/benchmark/synthetic_benchmark_harness.dart';
import 'package:local_bluey/services/local_semantic_file_retrieval.dart';

class _FakeIndex implements LocalSemanticFileIndex {
  _FakeIndex(this.responses);

  final Map<String, LocalSemanticRetrievalResult> responses;
  int invocations = 0;

  @override
  LocalSemanticRetrievalResult search(String query) {
    invocations++;
    return responses[query] ?? const LocalSemanticRetrievalResult.notFound();
  }
}

class _FakeClock {
  int current = 0;
  int read() {
    final result = current;
    current += 10;
    return result;
  }
}

void main() {
  test('seeded fake clock yields identical traces precision recall and latency', () {
    SyntheticBenchmarkReport benchmark() {
      final index = _FakeIndex({
        'alpha': LocalSemanticRetrievalResult.success(hits: [
          const LocalSemanticHit(path: 'a', score: 0.8),
          const LocalSemanticHit(path: 'extra', score: 0.2),
        ]),
        'beta': LocalSemanticRetrievalResult.success(hits: [
          const LocalSemanticHit(path: 'b', score: 0.9),
        ]),
      });
      final clock = _FakeClock();
      return SyntheticBenchmarkHarness(
        retrieval: LocalSemanticFileRetrieval(index: index),
        elapsedClockMicroseconds: clock.read,
      ).run(
        cases: [
          SyntheticBenchmarkCase(query: 'alpha', expectedPaths: {'a'}),
          SyntheticBenchmarkCase(query: 'beta', expectedPaths: {'b', 'missing'}),
        ],
        seed: 42,
        timeoutMicroseconds: 100,
      );
    }

    final first = benchmark();
    final second = benchmark();
    expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    expect(first.truePositives, 2);
    expect(first.falsePositives, 1);
    expect(first.falseNegatives, 1);
    expect(first.precision, closeTo(2 / 3, 0.000001));
    expect(first.recall, closeTo(2 / 3, 0.000001));
    expect(first.totalMicroseconds, 20);
  });

  test('invalid input timeout and cancellation have explicit outcomes', () {
    final index = _FakeIndex({});
    final clock = _FakeClock();
    final harness = SyntheticBenchmarkHarness(
      retrieval: LocalSemanticFileRetrieval(index: index),
      elapsedClockMicroseconds: clock.read,
    );
    expect(
      () => harness.run(
        cases: [SyntheticBenchmarkCase(query: ' ', expectedPaths: {})],
        seed: 0,
        timeoutMicroseconds: 10,
      ),
      throwsArgumentError,
    );
    final timeout = harness.run(
      cases: [SyntheticBenchmarkCase(query: 'offline', expectedPaths: {'a'})],
      seed: 1,
      timeoutMicroseconds: 5,
    );
    expect(timeout.traces.single.status, 'timeout');
    expect(timeout.falseNegatives, 1);
    expect(index.invocations, 1);

    final cancelled = harness.run(
      cases: [SyntheticBenchmarkCase(query: 'offline', expectedPaths: {})],
      seed: 1,
      timeoutMicroseconds: 100,
      isCancelled: () => true,
    );
    expect(cancelled.traces.single.status, 'cancelled');
    expect(index.invocations, 1);
  });

  test('offline in-memory seam performs no egress persistence or automatic action', () {
    final index = _FakeIndex({
      'offline': LocalSemanticRetrievalResult.success(hits: [
        const LocalSemanticHit(path: 'local.txt', score: 1),
      ]),
    });
    final clock = _FakeClock();
    final report = SyntheticBenchmarkHarness(
      retrieval: LocalSemanticFileRetrieval(index: index),
      elapsedClockMicroseconds: clock.read,
    ).run(
      cases: [
        SyntheticBenchmarkCase(query: 'offline', expectedPaths: {'local.txt'}),
      ],
      seed: 7,
      timeoutMicroseconds: 100,
    );
    expect(report.traces.single.status, 'success');
    expect(report.traces.single.predictedPaths, ['local.txt']);
    expect(index.invocations, 1);
    expect(jsonEncode(report.toJson()), isNot(contains('secret')));
  });
}
