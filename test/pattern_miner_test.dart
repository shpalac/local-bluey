import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/pattern_miner.dart';

/// One "A then B" sequence on [day], [hour] (UTC), seconds apart.
List<ObservedStep> _ab(int day, {int hour = 9, String context = ''}) {
  final t = DateTime.utc(2026, 3, 1 + day, hour);
  return [
    ObservedStep(fingerprint: 'A', at: t, context: context),
    ObservedStep(
      fingerprint: 'B',
      at: t.add(const Duration(seconds: 30)),
      context: context,
    ),
  ];
}

void main() {
  const miner = PatternMiner();

  test('the same sequence on three distinct days is detected', () {
    final result = miner.mine([..._ab(0), ..._ab(1), ..._ab(2)]);
    expect(result, hasLength(1));
    expect(result.single.sequence, ['A', 'B']);
    expect(result.single.occurrences, 3);
    expect(result.single.distinctDays, 3);
    expect(result.single.id, '@A>B');
  });

  test(
    'below the day threshold is never reported, however often it repeats',
    () {
      final sameDay = [for (var h = 0; h < 6; h++) ..._ab(0, hour: 8 + h)];
      expect(miner.mine(sameDay), isEmpty);
      expect(miner.mine([..._ab(0), ..._ab(1)]), isEmpty);
    },
  );

  test('below the occurrence threshold is not reported', () {
    const strict = PatternMiner(minOccurrences: 4, minDistinctDays: 3);
    expect(strict.mine([..._ab(0), ..._ab(1), ..._ab(2)]), isEmpty);
  });

  test('input order does not matter and the result is deterministic', () {
    final steps = [..._ab(0), ..._ab(1), ..._ab(2)];
    final a = miner.mine(steps).map((c) => c.id).toList();
    final b = miner.mine(steps.reversed).map((c) => c.id).toList();
    expect(b, a);
    expect(miner.mine(steps).map((c) => c.id), a);
  });

  test('a long pause or another context splits runs', () {
    final apart = [
      for (var d = 0; d < 3; d++) ...[
        ObservedStep(fingerprint: 'A', at: DateTime.utc(2026, 3, 1 + d, 9)),
        ObservedStep(fingerprint: 'B', at: DateTime.utc(2026, 3, 1 + d, 9, 30)),
      ],
    ];
    expect(miner.mine(apart), isEmpty);
    final mixed = [
      for (var d = 0; d < 3; d++) ...[
        ObservedStep(
          fingerprint: 'A',
          at: DateTime.utc(2026, 3, 1 + d, 9),
          context: 'one',
        ),
        ObservedStep(
          fingerprint: 'B',
          at: DateTime.utc(2026, 3, 1 + d, 9, 0, 10),
          context: 'two',
        ),
      ],
    ];
    expect(miner.mine(mixed), isEmpty);
  });

  test('contexts are mined separately', () {
    final both = [
      for (var d = 0; d < 3; d++) ..._ab(d, context: 'x'),
      for (var d = 0; d < 3; d++) ..._ab(d, hour: 14, context: 'y'),
    ];
    final ids = miner.mine(both).map((c) => c.id).toList()..sort();
    expect(ids, ['x@A>B', 'y@A>B']);
  });

  test('a longer sequence absorbs its identical-count parts', () {
    final abc = [
      for (var d = 0; d < 3; d++) ...[
        ObservedStep(fingerprint: 'A', at: DateTime.utc(2026, 3, 1 + d, 9)),
        ObservedStep(
          fingerprint: 'B',
          at: DateTime.utc(2026, 3, 1 + d, 9, 0, 5),
        ),
        ObservedStep(
          fingerprint: 'C',
          at: DateTime.utc(2026, 3, 1 + d, 9, 0, 10),
        ),
      ],
    ];
    expect(miner.mine(abc).map((c) => c.id), ['@A>B>C']);
  });

  test('malformed steps are dropped: empty and oversized fingerprints', () {
    final bad = [
      for (var d = 0; d < 3; d++) ...[
        ObservedStep(fingerprint: '', at: DateTime.utc(2026, 3, 1 + d, 9)),
        ObservedStep(
          fingerprint: 'x' * 129,
          at: DateTime.utc(2026, 3, 1 + d, 9, 0, 5),
        ),
      ],
    ];
    expect(miner.mine(bad), isEmpty);
    expect(miner.mine(const []), isEmpty);
  });

  test('only the most recent maxSteps are mined', () {
    const tiny = PatternMiner(maxSteps: 4);
    // Three days of A,B but only the last 4 steps (day 1 and day 2) are kept.
    expect(tiny.mine([..._ab(0), ..._ab(1), ..._ab(2)]), isEmpty);
  });

  test(
    'days are UTC days, so one late-night burst across midnight counts twice',
    () {
      final steps = [
        ObservedStep(
          fingerprint: 'A',
          at: DateTime.utc(2026, 3, 1, 23, 59, 50),
        ),
        ObservedStep(
          fingerprint: 'B',
          at: DateTime.utc(2026, 3, 1, 23, 59, 55),
        ),
        ObservedStep(fingerprint: 'A', at: DateTime.utc(2026, 3, 2, 0, 0, 5)),
        ObservedStep(fingerprint: 'B', at: DateTime.utc(2026, 3, 2, 0, 0, 10)),
      ];
      const loose = PatternMiner(minOccurrences: 2, minDistinctDays: 2);
      final result = loose.mine(steps);
      expect(result.map((c) => c.id), contains('@A>B'));
      expect(result.firstWhere((c) => c.id == '@A>B').distinctDays, 2);
    },
  );
}
