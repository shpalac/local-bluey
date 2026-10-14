import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/local_semantic_file_retrieval.dart';

class FakeIndex implements LocalSemanticFileIndex {
  @override
  LocalSemanticRetrievalResult search(String query) {
    if (query == 'notes') {
      return const LocalSemanticRetrievalResult.success(
        path: '/local/notes.txt',
      );
    }
    return const LocalSemanticRetrievalResult.notFound();
  }
}

void main() {
  test('returns invalid input for blank query', () {
    final retrieval = LocalSemanticFileRetrieval(index: FakeIndex());

    expect(retrieval.search(' '), isA<LocalSemanticInvalidInput>());
  });

  test('returns grounded local path from index result', () {
    final retrieval = LocalSemanticFileRetrieval(index: FakeIndex());

    final result = retrieval.search('notes');

    expect(result, isA<LocalSemanticSuccess>());
    expect((result as LocalSemanticSuccess).path, '/local/notes.txt');
  });
}
