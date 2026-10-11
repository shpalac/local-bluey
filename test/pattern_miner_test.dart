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
  final miner = PatternMiner();

  test('the same sequence on three distinct days is detected', () {
    final result = miner.mine([..._ab(0), ..._ab(1), ..._ab(2)]);
    expect(result, hasLength(1));
    expect(result.single.sequence, ['A', 'B']);
    expect(result.single.occurrences, 3);
    expect(result.single.distinctDays, 3);
    expect(result.single.id, '0:|1:A|1:B');
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
    final strict = PatternMiner(minOccurrences: 4, minDistinctDays: 3);
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
    expect(ids, ['1:x|1:A|1:B', '1:y|1:A|1:B']);
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
    expect(miner.mine(abc).map((c) => c.id), ['0:|1:A|1:B|1:C']);
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
    final tiny = PatternMiner(maxSteps: 4);
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
      final loose = PatternMiner(minOccurrences: 2, minDistinctDays: 2);
      final result = loose.mine(steps);
      expect(result.map((c) => c.id), contains('0:|1:A|1:B'));
      expect(result.firstWhere((c) => c.id == '0:|1:A|1:B').distinctDays, 2);
    },
  );

  group('adversarial and boundary inputs', () {
    List<ObservedStep> run(String ctx, List<String> fps, int day) {
      final t = DateTime.utc(2026, 3, 1 + day, 9);
      return [
        for (var k = 0; k < fps.length; k++)
          ObservedStep(
            fingerprint: fps[k],
            at: t.add(Duration(seconds: k * 10)),
            context: ctx,
          ),
      ];
    }

    test('delimiter characters never merge distinct sequences or contexts', () {
      final m = PatternMiner(minOccurrences: 1, minDistinctDays: 1);
      // Old encoding joined with U+0001: ["a\u0001b", "c"] vs ["a", "b\u0001c"].
      final steps = [
        ...run('', ['a\u0001b', 'c'], 0),
        ...run('', ['a', 'b\u0001c'], 1),
        // Context vs fingerprint boundary: U+0000.
        ...run('x\u0000y', ['p', 'q'], 2),
        ...run('x', ['y\u0000p', 'q'], 3),
        // Old public id joined with @ and >.
        ...run('c@a', ['b', 'd'], 4),
        ...run('c', ['a@b', 'd'], 5),
        ...run('', ['a>b', 'c'], 6),
        ...run('', ['a', 'b>c'], 7),
      ];
      final result = m.mine(steps);
      final ids = result.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(result.every((c) => c.occurrences == 1), isTrue);
      expect(result.length, 8);
    });

    test('invalid configuration throws in release mode too', () {
      expect(() => PatternMiner(minLength: 0), throwsArgumentError);
      expect(
        () => PatternMiner(minLength: 3, maxLength: 2),
        throwsArgumentError,
      );
      expect(() => PatternMiner(minOccurrences: 0), throwsArgumentError);
      expect(() => PatternMiner(minDistinctDays: 0), throwsArgumentError);
      expect(() => PatternMiner(maxSteps: -1), throwsArgumentError);
      expect(() => PatternMiner(maxSteps: 0), throwsArgumentError);
      expect(() => PatternMiner(maxFingerprintLength: 0), throwsArgumentError);
      expect(
        () => PatternMiner(maxStepGap: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => PatternMiner(maxSteps: 10, maxInputSteps: 5),
        throwsArgumentError,
      );
      expect(PatternMiner(maxStepGap: Duration.zero), isNotNull);
    });

    test('more than maxInputSteps valid steps throws, even from a stream', () {
      final m = PatternMiner(maxSteps: 3, maxInputSteps: 5);
      final t = DateTime.utc(2026, 3, 1);
      expect(
        () => m.mine(
          Iterable.generate(
            6,
            (i) => ObservedStep(
              fingerprint: 'A',
              at: t.add(Duration(seconds: i)),
            ),
          ),
        ),
        throwsArgumentError,
      );
      // An unbounded input stops at the limit instead of running forever.
      expect(
        () => m.mine(
          Iterable.generate(
            1 << 30,
            (i) => ObservedStep(
              fingerprint: 'A',
              at: t.add(Duration(seconds: i)),
            ),
          ),
        ),
        throwsArgumentError,
      );
      // Invalid steps do not count against the input bound.
      final ok = [
        for (var i = 0; i < 20; i++) ObservedStep(fingerprint: '', at: t),
        ObservedStep(fingerprint: 'A', at: t),
      ];
      expect(m.mine(ok), isEmpty);
    });

    test('exactly maxInputSteps valid steps is accepted', () {
      final m = PatternMiner(maxSteps: 4, maxInputSteps: 4);
      expect(m.mine([..._ab(0), ..._ab(1)]), isEmpty);
    });

    test('equal-time steps keep input order, so order can change results', () {
      final m = PatternMiner(minOccurrences: 3, minDistinctDays: 3);
      List<ObservedStep> day(int d, List<String> order) {
        final t = DateTime.utc(2026, 3, 1 + d, 9);
        return [for (final f in order) ObservedStep(fingerprint: f, at: t)];
      }

      final ab = [
        for (var d = 0; d < 3; d++) ...day(d, ['A', 'B']),
      ];
      final ba = [
        for (var d = 0; d < 3; d++) ...day(d, ['B', 'A']),
      ];
      expect(m.mine(ab).single.sequence, ['A', 'B']);
      expect(m.mine(ba).single.sequence, ['B', 'A']);
    });

    test('overlapping occurrences are counted and attributed to start day', () {
      final m = PatternMiner(minOccurrences: 2, minDistinctDays: 1);
      final t = DateTime.utc(2026, 3, 1, 23, 59, 50);
      final steps = [
        for (var i = 0; i < 3; i++)
          ObservedStep(
            fingerprint: 'A',
            at: t.add(Duration(seconds: i * 10)),
          ),
      ];
      // A,A,A at 23:59:50, 00:00:00, 00:00:10: A>A starts on day 1 and day 2.
      final r = m.mine(steps).firstWhere((c) => c.sequence.length == 2);
      expect(r.occurrences, 2);
      expect(r.distinctDays, 2);
    });
  });
}
