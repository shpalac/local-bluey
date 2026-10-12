import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/pattern_miner.dart';
import 'package:local_bluey/services/suggestion_ranker.dart';

PatternCandidate c(String ctx, List<String> seq, int occ, int days) =>
    PatternCandidate(
      context: ctx,
      sequence: seq,
      occurrences: occ,
      distinctDays: days,
    );

void main() {
  final now = DateTime.utc(2030, 1, 10, 12);
  SuggestionRanker ranker({int cap = 5, Duration? cd}) => SuggestionRanker(
    cooldown: cd ?? const Duration(hours: 24),
    maxEligible: cap,
  );

  List<String> ids(List<SuggestionDecision> r, SuggestionVerdict v) =>
      r.where((d) => d.verdict == v).map((d) => d.candidate.id).toList();

  test('ranks by days, occurrences, length, id regardless of input order', () {
    final a = c('x', ['a', 'b'], 4, 2);
    final b = c('x', ['c', 'd'], 3, 3);
    final d = c('x', ['e', 'f', 'g'], 4, 2);
    final e = c('x', ['a', 'a'], 4, 2);
    final all = [a, b, d, e];
    final first = ranker().rank(all, SuppressionSnapshot(), now);
    final second = ranker().rank(all.reversed, SuppressionSnapshot(), now);
    List<String> order(List<SuggestionDecision> r) =>
        r.map((x) => x.candidate.id).toList();
    expect(order(first), order(second));
    expect(first.first.candidate, b);
    expect(first[1].candidate, d);
    expect(first.every((x) => x.isRankEligible), isTrue);
  });

  test('duplicate ids are dropped after the first', () {
    final r = ranker().rank(
      [
        c('x', ['a'], 3, 2),
        c('x', ['a'], 3, 2),
      ],
      SuppressionSnapshot(),
      now,
    );
    expect(r.where((d) => d.isRankEligible).length, 1);
    expect(ids(r, SuggestionVerdict.duplicate).length, 1);
  });

  test('same display text with delimiter chars is not a duplicate', () {
    final r = ranker().rank(
      [
        c('a', ['b|c'], 3, 2),
        c('a|1:b', ['c'], 3, 2),
      ],
      SuppressionSnapshot(),
      now,
    );
    expect(r.where((d) => d.isRankEligible).length, 2);
  });

  test('dismissal hides until the exact cooldown boundary', () {
    final cand = c('x', ['a'], 3, 2);
    final dismissedAt = now.subtract(const Duration(hours: 24));
    final snap = SuppressionSnapshot(dismissedAt: {cand.id: dismissedAt});
    // exactly at cooldown: no longer suppressed
    expect(ranker().rank([cand], snap, now).single.isRankEligible, isTrue);
    // one microsecond before: still dismissed
    final r = ranker().rank(
      [cand],
      snap,
      now.subtract(const Duration(microseconds: 1)),
    );
    expect(r.single.verdict, SuggestionVerdict.dismissed);
  });

  test('clock moved backwards keeps a dismissal active', () {
    final cand = c('x', ['a'], 3, 2);
    final snap = SuppressionSnapshot(
      dismissedAt: {cand.id: now.add(const Duration(days: 30))},
    );
    expect(
      ranker().rank([cand], snap, now).single.verdict,
      SuggestionVerdict.dismissed,
    );
  });

  test('never-context hides every candidate in that context only', () {
    final r = ranker().rank(
      [
        c('mail', ['a'], 9, 9),
        c('chat', ['a'], 3, 2),
      ],
      SuppressionSnapshot(neverContexts: {'mail'}),
      now,
    );
    expect(ids(r, SuggestionVerdict.neverContext).length, 1);
    expect(r.first.candidate.context, 'chat');
    expect(r.first.isRankEligible, isTrue);
  });

  test('cap marks the rest overCap and cap 0 offers nothing', () {
    final all = [
      c('x', ['a'], 5, 5),
      c('x', ['b'], 4, 4),
      c('x', ['c'], 3, 3),
    ];
    final r = ranker(cap: 2).rank(all, SuppressionSnapshot(), now);
    expect(r.where((d) => d.isRankEligible).length, 2);
    expect(ids(r, SuggestionVerdict.overCap).length, 1);
    final none = ranker(cap: 0).rank(all, SuppressionSnapshot(), now);
    expect(none.any((d) => d.isRankEligible), isFalse);
  });

  test('invalid candidates are never eligible', () {
    final r = ranker().rank(
      [
        c('x', [], 3, 2),
        c('x', [''], 3, 2),
        c('x', ['a'], 0, 0),
        c('x', ['a'], 2, 3),
      ],
      SuppressionSnapshot(),
      now,
    );
    expect(r.where((d) => d.verdict == SuggestionVerdict.invalid).length, 4);
    expect(r.any((d) => d.isRankEligible), isFalse);
  });

  test('snapshot is copied: later mutation of inputs has no effect', () {
    final cand = c('x', ['a'], 3, 2);
    final map = <String, DateTime>{};
    final never = <String>{};
    final snap = SuppressionSnapshot(dismissedAt: map, neverContexts: never);
    map[cand.id] = now;
    never.add('x');
    expect(ranker().rank([cand], snap, now).single.isRankEligible, isTrue);
    expect(() => snap.neverContexts.add('y'), throwsUnsupportedError);
  });

  test('bad constructor arguments are rejected', () {
    expect(
      () => SuggestionRanker(
        cooldown: const Duration(seconds: -1),
        maxEligible: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => SuggestionRanker(
        cooldown: Duration.zero,
        maxEligible: -1,
        maxCandidates: 1,
      ),
      throwsArgumentError,
    );
  });

  test('negative candidate limit is rejected', () {
    expect(
      () => SuggestionRanker(
        cooldown: Duration.zero,
        maxEligible: 1,
        maxCandidates: -1,
      ),
      throwsArgumentError,
    );
  });

  test('exactly the limit is accepted, one more throws', () {
    final two = [
      c('x', ['a'], 3, 2),
      c('x', ['b'], 3, 2),
    ];
    expect(ranker(limit: 2).rank(two, SuppressionSnapshot(), now).length, 2);
    expect(
      () => ranker(limit: 1).rank(two, SuppressionSnapshot(), now),
      throwsA(isA<CandidateLimitExceeded>()),
    );
    expect(
      () => ranker(limit: 0).rank(two, SuppressionSnapshot(), now),
      throwsA(isA<CandidateLimitExceeded>()),
    );
    expect(
      ranker(limit: 0).rank(const [], SuppressionSnapshot(), now),
      isEmpty,
    );
  });

  test('endless lazy generator stops at the limit without finishing', () {
    var visited = 0;
    Iterable<PatternCandidate> endless() sync* {
      while (true) {
        visited++;
        yield c('x', ['t$visited'], 3, 2);
      }
    }

    expect(
      () => ranker(limit: 5).rank(endless(), SuppressionSnapshot(), now),
      throwsA(isA<CandidateLimitExceeded>()),
    );
    // Visited exactly limit + 1: five accepted, the sixth triggers the throw.
    expect(visited, 6);
  });
}
