import 'retrieval_models.dart';

class LocalSemanticRetrieval {
  const LocalSemanticRetrieval();

  Future<List<RetrievalResult>> search({
    required String query,
    required List<RetrievalDocument> documents,
    Duration timeout = const Duration(seconds: 1),
    bool cancelled = false,
  }) async {
    if (query.trim().isEmpty) {
      throw const RetrievalFailure(RetrievalFailureType.invalidInput);
    }

    if (cancelled) {
      throw const RetrievalFailure(RetrievalFailureType.cancelled);
    }

    return Future<List<RetrievalResult>>(() {
      final terms = _tokens(query);
      final results = <RetrievalResult>[];

      for (final document in documents) {
        final score = _score(terms, document.content);
        if (score > 0) {
          results.add(
            RetrievalResult(
              path: document.path,
              score: score,
            ),
          );
        }
      }

      results.sort((a, b) => b.score.compareTo(a.score));
      return results;
    }).timeout(
      timeout,
      onTimeout: () {
        throw const RetrievalFailure(RetrievalFailureType.timeout);
      },
    );
  }

  Set<String> _tokens(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toSet();
  }

  double _score(Set<String> queryTerms, String content) {
    final contentTerms = _tokens(content);
    if (queryTerms.isEmpty || contentTerms.isEmpty) {
      return 0;
    }

    return queryTerms.intersection(contentTerms).length / queryTerms.length;
  }
}
