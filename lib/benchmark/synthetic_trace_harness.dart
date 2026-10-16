/// Local-only, reproducible synthetic execution trace harness.
library;

import 'synthetic_benchmark.dart';

enum SyntheticExit {
  success,
  invalidInput,
  offline,
  timeout,
  permissionDenied,
  cancelled,
  restarted,
}

abstract interface class BenchmarkClock {
  Duration get elapsed;
}

class FakeBenchmarkClock implements BenchmarkClock {
  Duration _elapsed = Duration.zero;

  @override
  Duration get elapsed => _elapsed;

  void advance(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Cannot go backwards');
    }
    _elapsed += duration;
  }
}

class SyntheticTrace {
  const SyntheticTrace({
    required this.id,
    required this.expected,
    required this.actual,
    required this.exit,
    required this.elapsed,
  });

  final String id;
  final SyntheticOutcome expected;
  final SyntheticOutcome actual;
  final SyntheticExit exit;
  final Duration elapsed;
}

class SyntheticTraceHarness {
  SyntheticTraceHarness(this.clock, {this.maxTraces = 10000}) {
    if (maxTraces <= 0 || maxTraces > 100000) {
      throw ArgumentError.value(maxTraces, 'maxTraces', 'Out of range');
    }
  }

  final BenchmarkClock clock;
  final int maxTraces;
  final List<SyntheticTrace> _traces = [];
  final Set<String> _ids = {};

  List<SyntheticTrace> get traces => List.unmodifiable(_traces);

  void record({
    required String id,
    required SyntheticOutcome expected,
    required SyntheticOutcome actual,
    required SyntheticExit exit,
    required Duration startedAt,
  }) {
    if (_traces.length >= maxTraces) {
      throw StateError('Synthetic trace capacity exceeded');
    }
    if (id.trim().isEmpty || !_ids.add(id)) {
      throw ArgumentError.value(id, 'id', 'Must be nonempty and unique');
    }
    final elapsed = clock.elapsed - startedAt;
    if (startedAt.isNegative || elapsed.isNegative) {
      _ids.remove(id);
      throw ArgumentError.value(startedAt, 'startedAt', 'Invalid fake time');
    }
    _traces.add(
      SyntheticTrace(
        id: id,
        expected: expected,
        actual: actual,
        exit: exit,
        elapsed: elapsed,
      ),
    );
  }

  SyntheticMetrics metrics() {
    return const SyntheticBenchmark().evaluate(
      _traces.map(
        (trace) => SyntheticSample(
          id: trace.id,
          expected: trace.expected,
          actual: trace.actual,
          elapsed: trace.elapsed,
        ),
      ),
    );
  }
}
