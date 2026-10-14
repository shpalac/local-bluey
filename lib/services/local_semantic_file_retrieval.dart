/// Deterministic local retrieval contract for BLU-029.
///
/// This module intentionally contains no embedding model or filesystem access.
/// It defines the safe boundary used by future local index implementations.
class LocalSemanticFileRetrieval {
  LocalSemanticFileRetrieval({required this.index});

  final LocalSemanticFileIndex index;

  LocalSemanticRetrievalResult search(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const LocalSemanticRetrievalResult.invalidInput();
    }

    return index.search(normalized);
  }
}

abstract interface class LocalSemanticFileIndex {
  LocalSemanticRetrievalResult search(String query);
}

/// A grounded local path with a finite relevance score in the range [0, 1].
class LocalSemanticHit {
  const LocalSemanticHit({required this.path, required this.score})
    : assert(path.length > 0),
      assert(score >= 0 && score <= 1);

  final String path;
  final double score;
}

sealed class LocalSemanticRetrievalResult {
  const LocalSemanticRetrievalResult();

  factory LocalSemanticRetrievalResult.success({
    required List<LocalSemanticHit> hits,
  }) = LocalSemanticSuccess;

  const factory LocalSemanticRetrievalResult.invalidInput() =
      LocalSemanticInvalidInput;

  const factory LocalSemanticRetrievalResult.notFound() = LocalSemanticNotFound;
}

class LocalSemanticSuccess extends LocalSemanticRetrievalResult {
  LocalSemanticSuccess({required List<LocalSemanticHit> hits})
    : hits = List.unmodifiable(_validateAndRank(hits)),
      super();

  /// Highest-scoring hit first, with path order breaking ties.
  final List<LocalSemanticHit> hits;

  static List<LocalSemanticHit> _validateAndRank(List<LocalSemanticHit> hits) {
    if (hits.isEmpty) {
      throw ArgumentError.value(hits, 'hits', 'Success requires at least one hit');
    }

    final ordered = List<LocalSemanticHit>.of(hits);
    for (final hit in ordered) {
      if (hit.path.trim().isEmpty ||
          !hit.score.isFinite ||
          hit.score < 0 ||
          hit.score > 1) {
        throw ArgumentError.value(
          hit,
          'hits',
          'Each hit needs a nonblank path and finite score in [0, 1]',
        );
      }
    }

    ordered.sort((left, right) {
      final scoreOrder = right.score.compareTo(left.score);
      return scoreOrder != 0 ? scoreOrder : left.path.compareTo(right.path);
    });
    return ordered;
  }
}

class LocalSemanticInvalidInput extends LocalSemanticRetrievalResult {
  const LocalSemanticInvalidInput() : super();
}

class LocalSemanticNotFound extends LocalSemanticRetrievalResult {
  const LocalSemanticNotFound() : super();
}
