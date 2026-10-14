import '../services/action_events.dart';
import '../services/pattern_miner.dart';

/// Connects normalized BLU-006 events to BLU-008 mining without persistence,
/// I/O, or capture permissions. Runtime capture remains owned by the caller.
class ActionPatternBenchmarkAdapter {
  const ActionPatternBenchmarkAdapter();

  List<PatternCandidate> mine(
    Iterable<ActionEvent> events, {
    PatternMiner? miner,
  }) {
    return (miner ?? PatternMiner()).mine(
      events.map(
        (event) => ObservedStep(
          fingerprint: '${event.kind.name}:${event.app}',
          at: event.at,
          context: event.sessionId.toString(),
        ),
      ),
    );
  }
}
