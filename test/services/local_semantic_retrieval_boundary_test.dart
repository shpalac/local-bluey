import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/local_semantic_file_retrieval.dart';

class _RankedIndex implements LocalSemanticFileIndex {
  _RankedIndex(this.onSearch);

  final LocalSemanticRetrievalResult Function(String query) onSearch;

  @override
  LocalSemanticRetrievalResult search(String query) => onSearch(query);
}

void main() {
  test('retrieval returns a separately immutable ranked snapshot', () {
    final source = <LocalSemanticHit>[
      const LocalSemanticHit(path: '/local/b.txt', score: 0.4),
      const LocalSemanticHit(path: '/local/a.txt', score: 0.8),
    ];
    final index = _RankedIndex(
      (_) => LocalSemanticRetrievalResult.success(hits: source),
    );
    final retrieval = LocalSemanticFileRetrieval(index: index);

    final first = retrieval.search('  files  ') as LocalSemanticSuccess;
    source.add(const LocalSemanticHit(path: '/local/c.txt', score: 1));
    final second = retrieval.search('files') as LocalSemanticSuccess;

    expect(first.hits.map((hit) => hit.path), [
      '/local/a.txt',
      '/local/b.txt',
    ]);
    expect(second.hits.map((hit) => hit.path), [
      '/local/c.txt',
      '/local/a.txt',
      '/local/b.txt',
    ]);
    expect(identical(first.hits, second.hits), isFalse);
    expect(() => first.hits.add(
      const LocalSemanticHit(path: '/local/new.txt', score: 0.5),
    ), throwsUnsupportedError);
  });

  test('retrieval forwards typed invalid and missing results unchanged', () {
    const invalid = LocalSemanticRetrievalResult.invalidInput();
    const missing = LocalSemanticRetrievalResult.notFound();
    final retrieval = LocalSemanticFileRetrieval(
      index: _RankedIndex((query) => query == 'invalid' ? invalid : missing),
    );

    expect(identical(retrieval.search('invalid'), invalid), isTrue);
    expect(identical(retrieval.search('missing'), missing), isTrue);
  });
}
