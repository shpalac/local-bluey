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

sealed class LocalSemanticRetrievalResult {
  const LocalSemanticRetrievalResult();

  const factory LocalSemanticRetrievalResult.success({
    required String path,
  }) = LocalSemanticSuccess;

  const factory LocalSemanticRetrievalResult.invalidInput() =
      LocalSemanticInvalidInput;

  const factory LocalSemanticRetrievalResult.notFound() = LocalSemanticNotFound;
}

class LocalSemanticSuccess extends LocalSemanticRetrievalResult {
  const LocalSemanticSuccess({required this.path}) : super();

  final String path;
}

class LocalSemanticInvalidInput extends LocalSemanticRetrievalResult {
  const LocalSemanticInvalidInput() : super();
}

class LocalSemanticNotFound extends LocalSemanticRetrievalResult {
  const LocalSemanticNotFound() : super();
}
