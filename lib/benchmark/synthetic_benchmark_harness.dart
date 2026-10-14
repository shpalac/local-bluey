import '../services/local_semantic_file_retrieval.dart';

/// One offline query with its expected local paths.
class SyntheticBenchmarkCase {
  SyntheticBenchmarkCase({required this.query, required Set<String> expectedPaths})
    : expectedPaths = Set.unmodifiable(expectedPaths);

  final String query;
  final Set<String> expectedPaths;
}

/// Immutable per-query result. A failed query contributes no predicted hits.
class SyntheticBenchmarkTrace {
  const SyntheticBenchmarkTrace({
    required this.query,
    required this.status,
    required this.elapsedMicroseconds,
    required this.predictedPaths,
  });

  final String query;
  final String status;
  final int elapsedMicroseconds;
  final List<String> predictedPaths;

  Map<String, Object> toJson() => {
    'query': query,
    'status': status,
    'elapsedMicroseconds': elapsedMicroseconds,
    'predictedPaths': predictedPaths,
  };
}

class SyntheticBenchmarkReport {
  const SyntheticBenchmarkReport({
    required this.traces,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
    required this.totalMicroseconds,
  });

  final List<SyntheticBenchmarkTrace> traces;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;
  final int totalMicroseconds;

  double get precision {
    final denominator = truePositives + falsePositives;
    return denominator == 0 ? 0 : truePositives / denominator;
  }

  double get recall {
    final denominator = truePositives + falseNegatives;
    return denominator == 0 ? 0 : truePositives / denominator;
  }

  Map<String, Object> toJson() => {
    'traces': traces.map((trace) => trace.toJson()).toList(),
    'truePositives': truePositives,
    'falsePositives': falsePositives,
    'falseNegatives': falseNegatives,
    'precision': precision,
    'recall': recall,
    'totalMicroseconds': totalMicroseconds,
  };
}

/// Exercises the actual local retrieval interface. Clock and cancellation are
/// injected; the harness has no network, storage, or platform dependencies.
class SyntheticBenchmarkHarness {
  const SyntheticBenchmarkHarness({
    required this.retrieval,
    required this.elapsedClockMicroseconds,
  });

  final LocalSemanticFileRetrieval retrieval;
  final int Function() elapsedClockMicroseconds;

  SyntheticBenchmarkReport run({
    required List<SyntheticBenchmarkCase> cases,
    required int seed,
    required int timeoutMicroseconds,
    bool Function()? isCancelled,
  }) {
    if (cases.isEmpty || timeoutMicroseconds <= 0) {
      throw ArgumentError('Cases must be nonempty and timeout positive');
    }
    for (final item in cases) {
      if (item.query.trim().isEmpty ||
          item.expectedPaths.any((path) => path.trim().isEmpty)) {
        throw ArgumentError('Queries and expected paths must be nonblank');
      }
    }

    final order = List<int>.generate(cases.length, (index) => index);
    var state = seed & 0x7fffffff;
    for (var index = order.length - 1; index > 0; index--) {
      state = (1103515245 * state + 12345) & 0x7fffffff;
      final target = state % (index + 1);
      final previous = order[index];
      order[index] = order[target];
      order[target] = previous;
    }

    final traces = <SyntheticBenchmarkTrace>[];
    var truePositives = 0;
    var falsePositives = 0;
    var falseNegatives = 0;
    var total = 0;

    for (final index in order) {
      final item = cases[index];
      final start = elapsedClockMicroseconds();
      if (isCancelled?.call() ?? false) {
        traces.add(SyntheticBenchmarkTrace(
          query: item.query,
          status: 'cancelled',
          elapsedMicroseconds: 0,
          predictedPaths: const [],
        ));
        break;
      }

      final result = retrieval.search(item.query);
      final end = elapsedClockMicroseconds();
      if (end < start) {
        throw StateError('Benchmark clock must be monotonic');
      }
      final elapsed = end - start;
      total += elapsed;

      final status = elapsed > timeoutMicroseconds
          ? 'timeout'
          : result is LocalSemanticSuccess
              ? 'success'
              : result is LocalSemanticNotFound
                  ? 'notFound'
                  : 'invalidInput';
      final predicted = status == 'success'
          ? (result as LocalSemanticSuccess)
              .hits
              .map((hit) => hit.path)
              .toSet()
              .toList()
            ..sort()
          : <String>[];
      final actual = predicted.toSet();
      truePositives += actual.intersection(item.expectedPaths).length;
      falsePositives += actual.difference(item.expectedPaths).length;
      falseNegatives += item.expectedPaths.difference(actual).length;
      traces.add(SyntheticBenchmarkTrace(
        query: item.query,
        status: status,
        elapsedMicroseconds: elapsed,
        predictedPaths: List.unmodifiable(predicted),
      ));
      if (status == 'timeout') {
        break;
      }
    }

    return SyntheticBenchmarkReport(
      traces: List.unmodifiable(traces),
      truePositives: truePositives,
      falsePositives: falsePositives,
      falseNegatives: falseNegatives,
      totalMicroseconds: total,
    );
  }
}
