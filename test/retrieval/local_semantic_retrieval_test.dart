import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/local_semantic_file_retrieval.dart';

void main() {
  test('missing file is never hallucinated', () {
    final retrieval = LocalSemanticFileRetrieval(index: _EmptyIndex());

    final result = retrieval.search('missing-file');

    expect(result, isA<LocalSemanticNotFound>());
  });

  test('invalid input is rejected', () {
    final retrieval = LocalSemanticFileRetrieval(index: _EmptyIndex());

    final result = retrieval.search('  ');

    expect(result, isA<LocalSemanticInvalidInput>());
  });

  test('cancelled request is rejected', () {
    final retrieval = LocalSemanticFileRetrieval(index: _CancelledIndex());

    final result = retrieval.search('content');

    expect(result, isA<LocalSemanticNotFound>());
  });

  test('retrieval only returns local grounded paths', () {
    final retrieval = LocalSemanticFileRetrieval(index: _SecretIndex());

    final result = retrieval.search('secret');

    final success = result as LocalSemanticSuccess;
    expect(success.hits.single.path, '/local/secret.txt');
    expect(success.hits.single.path.startsWith('http'), isFalse);
  });
}

class _EmptyIndex implements LocalSemanticFileIndex {
  @override
  LocalSemanticRetrievalResult search(String query) {
    return const LocalSemanticRetrievalResult.notFound();
  }
}

class _CancelledIndex extends _EmptyIndex {}

class _SecretIndex implements LocalSemanticFileIndex {
  @override
  LocalSemanticRetrievalResult search(String query) {
    return LocalSemanticRetrievalResult.success(
      hits: const [
        LocalSemanticHit(path: '/local/secret.txt', score: 1),
      ],
    );
  }
}
