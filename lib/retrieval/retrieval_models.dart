class RetrievalDocument {
  const RetrievalDocument({
    required this.path,
    required this.content,
  });

  final String path;
  final String content;
}

class RetrievalResult {
  const RetrievalResult({
    required this.path,
    required this.score,
  });

  final String path;
  final double score;
}

enum RetrievalFailureType {
  invalidInput,
  missingDocument,
  cancelled,
  timeout,
}

class RetrievalFailure implements Exception {
  const RetrievalFailure(this.type);

  final RetrievalFailureType type;
}
