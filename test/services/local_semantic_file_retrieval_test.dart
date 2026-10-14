import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/local_semantic_file_retrieval.dart';

class FakeIndex implements LocalSemanticFileIndex {
  String? receivedQuery;

  @override
  LocalSemanticRetrievalResult search(String query) {
    receivedQuery = query;
    if (query == 'notes') {
      return LocalSemanticRetrievalResult.success(
        hits: const [
          LocalSemanticHit(path: '/local/other.txt', score: 0.2),
          LocalSemanticHit(path: '/local/notes.txt', score: 0.9),
          LocalSemanticHit(path: '/local/alpha.txt', score: 0.9),
        ],
      );
    }
    return const LocalSemanticRetrievalResult.notFound();
  }
}

void main() {
  test('success returns highest score first with deterministic path ties', () {
    final index = FakeIndex();
    final result = LocalSemanticFileRetrieval(index: index).search('  notes  ');

    expect(index.receivedQuery, 'notes');
    expect(result, isA<LocalSemanticSuccess>());
    final hits = (result as LocalSemanticSuccess).hits;
    expect(
      hits.map((hit) => hit.path),
      ['/local/alpha.txt', '/local/notes.txt', '/local/other.txt'],
    );
    expect(hits.map((hit) => hit.score), [0.9, 0.9, 0.2]);
    expect(() => hits.clear(), throwsUnsupportedError);
  });

  test('success rejects empty results and out-of-range or nonfinite scores', () {
    expect(
      () => LocalSemanticRetrievalResult.success(hits: const []),
      throwsArgumentError,
    );
    for (final score in [-0.01, 1.01, double.nan, double.infinity]) {
      expect(
        () => LocalSemanticRetrievalResult.success(
          hits: [LocalSemanticHit(path: '/local/document.txt', score: score)],
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => LocalSemanticRetrievalResult.success(
        hits: const [LocalSemanticHit(path: ' ', score: 0.5)],
      ),
      throwsArgumentError,
    );
    final result = LocalSemanticRetrievalResult.success(
      hits: const [
        LocalSemanticHit(path: '/local/zero.txt', score: 0),
        LocalSemanticHit(path: '/local/one.txt', score: 1),
      ],
    ) as LocalSemanticSuccess;
    expect(result.hits.map((hit) => hit.score), [1, 0]);
  });

  test('blank queries remain invalid and never invoke index', () {
    final index = FakeIndex();
    final retrieval = LocalSemanticFileRetrieval(index: index);

    expect(retrieval.search(' \t\n '), isA<LocalSemanticInvalidInput>());
    expect(index.receivedQuery, isNull);
  });

  test('missing matches remain notFound without invented hits', () {
    final retrieval = LocalSemanticFileRetrieval(index: FakeIndex());

    expect(retrieval.search('absent'), isA<LocalSemanticNotFound>());
  });
}
