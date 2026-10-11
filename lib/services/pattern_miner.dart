/// One observed step for pattern mining (BLU-008). The fingerprint is an
/// opaque, content-free label chosen by the caller (for example a kind and
/// app name). The miner never looks inside it.
class ObservedStep {
  const ObservedStep({
    required this.fingerprint,
    required this.at,
    this.context = '',
  });

  /// Opaque label for the step.
  final String fingerprint;

  /// When the step happened.
  final DateTime at;

  /// Optional grouping label; patterns never span two contexts.
  final String context;
}

/// A repeated sequence that passed every threshold.
class PatternCandidate {
  const PatternCandidate({
    required this.context,
    required this.sequence,
    required this.occurrences,
    required this.distinctDays,
  });

  /// Context the sequence was seen in.
  final String context;

  /// The repeated fingerprints, in order.
  final List<String> sequence;

  /// How many times the sequence occurred in total.
  final int occurrences;

  /// On how many distinct UTC days it occurred.
  final int distinctDays;

  /// Stable, collision-free id for the same context and sequence. Every part
  /// is length-prefixed, so no choice of characters in a context or
  /// fingerprint lets two different candidates share an id.
  String get id => _encode(context, sequence);

  @override
  String toString() => 'PatternCandidate($id x$occurrences/${distinctDays}d)';
}

String _encode(String context, List<String> sequence) {
  final b = StringBuffer('${context.length}:$context');
  for (final f in sequence) {
    b.write('|${f.length}:$f');
  }
  return b.toString();
}

/// Deterministic, pure-Dart repeated-sequence miner (BLU-008).
///
/// It only counts. It reads no screen content, keeps nothing between calls,
/// does no I/O and uses no clock or randomness, so the same input always
/// gives the same output. A sequence is reported only when it reaches both
/// [minOccurrences] and [minDistinctDays]; anything below stays unreported.
///
/// Semantics worth knowing:
/// - Steps are ordered by time. Steps with an equal time keep their input
///   order, so equal-time steps with different fingerprints can give a
///   different result if the caller passes them in a different order.
/// - Occurrences are counted with overlap: in A, A, A the sequence A>A
///   occurs twice.
/// - An occurrence belongs to the UTC day of its first step.
/// - Bounds: at most [maxInputSteps] valid steps may be passed in (more
///   throws, nothing is silently dropped); of those only the most recent
///   [maxSteps] are mined.
class PatternMiner {
  PatternMiner({
    this.minLength = 2,
    this.maxLength = 5,
    this.minOccurrences = 3,
    this.minDistinctDays = 3,
    this.maxStepGap = const Duration(minutes: 5),
    this.maxSteps = 5000,
    this.maxFingerprintLength = 128,
    this.maxInputSteps = 50000,
  }) {
    void positive(String name, int v) {
      if (v < 1) throw ArgumentError.value(v, name, 'must be at least 1');
    }

    positive('minLength', minLength);
    positive('maxLength', maxLength);
    positive('minOccurrences', minOccurrences);
    positive('minDistinctDays', minDistinctDays);
    positive('maxSteps', maxSteps);
    positive('maxFingerprintLength', maxFingerprintLength);
    positive('maxInputSteps', maxInputSteps);
    if (maxLength < minLength) {
      throw ArgumentError.value(maxLength, 'maxLength', 'must be >= minLength');
    }
    if (maxInputSteps < maxSteps) {
      throw ArgumentError.value(
        maxInputSteps,
        'maxInputSteps',
        'must be >= maxSteps',
      );
    }
    if (maxStepGap.isNegative) {
      throw ArgumentError.value(
        maxStepGap,
        'maxStepGap',
        'must not be negative',
      );
    }
  }

  /// Most valid steps accepted per call; one more throws [ArgumentError].
  final int maxInputSteps;

  /// Shortest sequence reported.
  final int minLength;

  /// Longest sequence considered.
  final int maxLength;

  /// Total occurrences needed.
  final int minOccurrences;

  /// Distinct UTC days needed. This is what separates a habit from a burst.
  final int minDistinctDays;

  /// A longer pause between two steps ends the current run.
  final Duration maxStepGap;

  /// Only the most recent steps are mined (mining work is bounded by this).
  final int maxSteps;

  /// Steps with a longer fingerprint are dropped, never truncated.
  final int maxFingerprintLength;

  /// Mines [steps]. Empty or oversized fingerprints are dropped. Throws
  /// [ArgumentError] when more than [maxInputSteps] valid steps are given, so
  /// the recent steps that win are never chosen silently.
  List<PatternCandidate> mine(Iterable<ObservedStep> steps) {
    final clean = <ObservedStep>[];
    for (final s in steps) {
      if (s.fingerprint.isEmpty ||
          s.fingerprint.length > maxFingerprintLength) {
        continue;
      }
      if (clean.length >= maxInputSteps) {
        throw ArgumentError.value(
          steps,
          'steps',
          'more than $maxInputSteps valid steps',
        );
      }
      clean.add(s);
    }
    // Stable sort by time; ties keep input order.
    final indexed = [for (var i = 0; i < clean.length; i++) (i, clean[i])];
    indexed.sort((a, b) {
      final c = a.$2.at.compareTo(b.$2.at);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    var ordered = [for (final e in indexed) e.$2];
    if (ordered.length > maxSteps) {
      ordered = ordered.sublist(ordered.length - maxSteps);
    }

    // Split into runs: same context, no pause longer than maxStepGap.
    final runs = <List<ObservedStep>>[];
    for (final step in ordered) {
      final run = runs.isEmpty ? null : runs.last;
      if (run != null &&
          run.last.context == step.context &&
          step.at.difference(run.last.at) <= maxStepGap) {
        run.add(step);
      } else {
        runs.add([step]);
      }
    }

    final counts = <String, _Tally>{};
    for (final run in runs) {
      for (var len = minLength; len <= maxLength; len++) {
        for (var i = 0; i + len <= run.length; i++) {
          final seq = [for (var k = i; k < i + len; k++) run[k].fingerprint];
          final key = _encode(run.first.context, seq);
          final t = counts.putIfAbsent(
            key,
            () => _Tally(run.first.context, seq),
          );
          t.occurrences++;
          t.days.add(_day(run[i].at));
        }
      }
    }

    final passed = [
      for (final t in counts.values)
        if (t.occurrences >= minOccurrences && t.days.length >= minDistinctDays)
          PatternCandidate(
            context: t.context,
            sequence: List.unmodifiable(t.sequence),
            occurrences: t.occurrences,
            distinctDays: t.days.length,
          ),
    ];
    // Drop a shorter sequence that sits inside a longer one with the same
    // counts: it is the same habit, not a second one.
    final kept = [
      for (final c in passed)
        if (!passed.any((o) => _absorbs(o, c))) c,
    ];
    kept.sort((a, b) {
      var c = b.distinctDays.compareTo(a.distinctDays);
      if (c != 0) return c;
      c = b.occurrences.compareTo(a.occurrences);
      if (c != 0) return c;
      c = b.sequence.length.compareTo(a.sequence.length);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return List.unmodifiable(kept);
  }

  static int _day(DateTime t) {
    final u = t.toUtc();
    return DateTime.utc(u.year, u.month, u.day).millisecondsSinceEpoch;
  }

  static bool _absorbs(PatternCandidate big, PatternCandidate small) {
    if (big.context != small.context ||
        big.sequence.length <= small.sequence.length ||
        big.occurrences != small.occurrences ||
        big.distinctDays != small.distinctDays) {
      return false;
    }
    for (var s = 0; s + small.sequence.length <= big.sequence.length; s++) {
      var match = true;
      for (var k = 0; k < small.sequence.length; k++) {
        if (big.sequence[s + k] != small.sequence[k]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }
}

class _Tally {
  _Tally(this.context, this.sequence);
  final String context;
  final List<String> sequence;
  int occurrences = 0;
  final Set<int> days = {};
}
