import 'pattern_miner.dart';

/// Why a candidate was not offered (BLU-009 groundwork).
enum SuggestionVerdict {
  /// Passed every check; safe to show as a read-only suggestion.
  eligible,

  /// Same candidate id appeared earlier in the input.
  duplicate,

  /// The caller marked this exact candidate as dismissed and the cooldown
  /// has not passed (or the clock moved backwards).
  dismissed,

  /// The caller marked this context as never-suggest.
  neverContext,

  /// Empty id parts or non-positive counts; never shown.
  invalid,

  /// Eligible, but beyond the display cap.
  overCap,
}

/// One ranked outcome. Order of a result list is the display order.
class SuggestionDecision {
  const SuggestionDecision(this.candidate, this.verdict);

  final PatternCandidate candidate;
  final SuggestionVerdict verdict;

  bool get isEligible => verdict == SuggestionVerdict.eligible;
}

/// Caller-supplied, in-memory suppression state. This module stores nothing:
/// who persists it, where, and for how long is a separate owner decision.
/// Unknown or unavailable state must be passed as a failure by the caller,
/// never as an empty snapshot.
class SuppressionSnapshot {
  SuppressionSnapshot({
    Map<String, DateTime> dismissedAt = const {},
    Set<String> neverContexts = const {},
  }) : dismissedAt = Map.unmodifiable(Map.of(dismissedAt)),
       neverContexts = Set.unmodifiable(Set.of(neverContexts));

  /// Candidate id -> when the user dismissed it.
  final Map<String, DateTime> dismissedAt;

  /// Exact context strings the user said never to suggest for.
  final Set<String> neverContexts;
}

/// Pure ranking, de-duplication and suppression of mined candidates.
///
/// It reads no clock (the caller passes [now]), does no I/O, keeps no state
/// and never acts: an eligible result is only something a UI may show. All
/// numbers are required constructor arguments; this class selects no
/// cooldown, cap or weight. Ranking is by distinct days, then occurrences,
/// then sequence length, then id, so the order is total and does not depend
/// on input order. Those counts are evidence, not a confidence value.
class SuggestionRanker {
  SuggestionRanker({required this.cooldown, required this.maxEligible}) {
    if (cooldown.isNegative) {
      throw ArgumentError.value(cooldown, 'cooldown', 'must not be negative');
    }
    if (maxEligible < 0) {
      throw ArgumentError.value(maxEligible, 'maxEligible', 'must be >= 0');
    }
  }

  /// How long a dismissal hides the same candidate.
  final Duration cooldown;

  /// At most this many results are eligible; the rest are [overCap].
  final int maxEligible;

  /// Returns every input candidate with a verdict, eligible ones first in
  /// display order, then the rest in the same total order.
  List<SuggestionDecision> rank(
    Iterable<PatternCandidate> candidates,
    SuppressionSnapshot suppression,
    DateTime now,
  ) {
    final sorted = candidates.toList()..sort(_compare);
    final seen = <String>{};
    final out = <SuggestionDecision>[];
    var eligible = 0;
    for (final c in sorted) {
      final SuggestionVerdict v;
      if (!_valid(c)) {
        v = SuggestionVerdict.invalid;
      } else if (!seen.add(c.id)) {
        v = SuggestionVerdict.duplicate;
      } else if (suppression.neverContexts.contains(c.context)) {
        v = SuggestionVerdict.neverContext;
      } else if (_dismissed(c.id, suppression, now)) {
        v = SuggestionVerdict.dismissed;
      } else if (eligible >= maxEligible) {
        v = SuggestionVerdict.overCap;
      } else {
        eligible++;
        v = SuggestionVerdict.eligible;
      }
      out.add(SuggestionDecision(c, v));
    }
    // Stable partition: eligible first, order inside each group is kept.
    return [
      ...out.where((d) => d.isEligible),
      ...out.where((d) => !d.isEligible),
    ];
  }

  bool _dismissed(String id, SuppressionSnapshot s, DateTime now) {
    final at = s.dismissedAt[id];
    if (at == null) return false;
    // A dismissal in the future means the clock moved back: stay hidden.
    if (at.isAfter(now)) return true;
    return now.difference(at) < cooldown;
  }

  static bool _valid(PatternCandidate c) =>
      c.sequence.isNotEmpty &&
      c.sequence.every((f) => f.isNotEmpty) &&
      c.occurrences > 0 &&
      c.distinctDays > 0 &&
      c.distinctDays <= c.occurrences;

  static int _compare(PatternCandidate a, PatternCandidate b) {
    var r = b.distinctDays.compareTo(a.distinctDays);
    if (r != 0) return r;
    r = b.occurrences.compareTo(a.occurrences);
    if (r != 0) return r;
    r = b.sequence.length.compareTo(a.sequence.length);
    if (r != 0) return r;
    return a.id.compareTo(b.id);
  }
}
