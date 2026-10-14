import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/retrieval/local_semantic_retrieval.dart';
import 'package:local_bluey/retrieval/retrieval_models.dart';

void main() {
  const retrieval = LocalSemanticRetrieval();

  test('missing file is never hallucinated', () async {
    final results = await retrieval.search(
      query: 'missing-file',
      documents: const [
        RetrievalDocument(
          path: '/docs/known.txt',
          content: 'known content',
        ),
      ],
    );

    expect(results, isEmpty);
    expect(results.any((item) => item.path == '/docs/missing.txt'), isFalse);
  });

  test('invalid input is rejected', () async {
    expect(
      () => retrieval.search(query: '  ', documents: const []),
      throwsA(isA<RetrievalFailure>()),
    );
  });

  test('cancelled request is rejected', () async {
    expect(
      () => retrieval.search(
        query: 'content',
        documents: const [],
        cancelled: true,
      ),
      throwsA(isA<RetrievalFailure>()),
    );
  });

  test('retrieval only returns local grounded paths', () async {
    final results = await retrieval.search(
      query: 'secret',
      documents: const [
        RetrievalDocument(
          path: '/local/secret.txt',
          content: 'secret value',
        ),
      ],
    );

    expect(results.single.path, '/local/secret.txt');
    expect(results.single.path.startsWith('http'), isFalse);
  });
}
