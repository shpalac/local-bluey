import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/file_index.dart';

void main() {
  test('ac3 the index stays transport-free over its granted local reads', () {
    final source = File('lib/services/file_index.dart').readAsStringSync();
    expect(source.length, greaterThan(0));
    expect(
      source.contains(RegExp("import '(package:http)")),
      isFalse,
      reason: 'the in-memory index must not gain transport access',
    );
    expect(
      source.contains(RegExp(r'HttpClient|writeAsBytes|writeAsString')),
      isFalse,
      reason: 'the index must not gain artifact writers',
    );
  });

  test('ac3 a revoked index exposes no citation surface for the corpus', () {
    final index = FileIndex();
    index.revoke();

    // After revocation the retrieval snapshot is empty and no corpus
    // secret can leak through search, counts or snapshot matching.
    expect(index.retrievalSnapshot(), isEmpty);
    for (final secret in [
      'hunter2',
      'sample@fixture.invalid',
      '4111-1111-1111-1111',
    ]) {
      expect(index.search(secret), isEmpty);
    }
    expect(index.documentCount, 0);
    expect(
      index.matchesRetrievalSnapshot({'notes.txt': 'hunter2 lives here'}),
      isFalse,
      reason: 'stale snapshots never keep matching after revocation',
    );
    expect(index.state, FileIndexState.disabled);
  });
}
