import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/benchmark/action_pattern_benchmark_adapter.dart';
import 'package:local_bluey/services/action_events.dart';
import 'package:local_bluey/services/pattern_miner.dart';

void main() {
  test('adapter maps normalized events into bounded pattern input', () {
    final adapter = const ActionPatternBenchmarkAdapter();
    final events = [
      for (var i = 0; i < 3; i++)
        ActionEvent(
          sequence: i,
          sessionId: 1,
          kind: ActionEventKind.appActivated,
          app: 'Editor',
          at: DateTime.utc(2026, 1, i + 1),
          confidence: 0.9,
        ),
    ];

    final result = adapter.mine(
      events,
      miner: PatternMiner(
        minOccurrences: 1,
        minDistinctDays: 1,
        minLength: 1,
        maxLength: 1,
      ),
    );

    expect(result, isNotEmpty);
    expect(result.single.sequence.single, contains('appActivated'));
  });
}
