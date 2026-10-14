import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/file_index.dart';
import 'package:local_bluey/services/local_semantic_retrieval.dart';

void main() {
  late Directory directory;
  late FileIndex index;
  late LocalSemanticRetriever retriever;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bluey-retrieval-');
    index = FileIndex();
    retriever = LocalSemanticRetriever(index);
  });

  tearDown(() async {
    index.revoke();
    await directory.delete(recursive: true);
  });

  test('missing file never hallucinated', () async {
    await File('${directory.path}/existing.txt')
        .writeAsString('garden watering schedule');
    await index.grant(directory, consent: true);
    final result = await retriever.retrieve('quantum spacecraft');
    expect(result.status, LocalRetrievalStatus.noMatches);
    expect(result.hits, isEmpty);
  });

  test('consent gate, grounded citation and ranked excerpt', () async {
    final file = File('${directory.path}/guide.txt');
    await file.writeAsString('blueberry pancakes with honey');
    expect((await retriever.retrieve('blueberry')).status,
        LocalRetrievalStatus.disabled);
    await index.grant(directory, consent: false);
    expect((await retriever.retrieve('blueberry')).hits, isEmpty);
    await index.grant(directory, consent: true);
    final result = await retriever.retrieve('blueberry');
    expect(result.status, LocalRetrievalStatus.ready);
    expect(result.hits.single.path, file.path);
    expect(result.hits.single.excerpt, contains('blueberry'));
    expect(result.hits.single.score, greaterThan(0));
  });

  test('invalid query and invalid limit fail closed', () async {
    await index.grant(directory, consent: true);
    expect((await retriever.retrieve(' ')).status,
        LocalRetrievalStatus.invalidQuery);
    expect((await retriever.retrieve('hello', limit: 0)).status,
        LocalRetrievalStatus.invalidQuery);
  });

  test('revocation and restart remove all results', () async {
    await File('${directory.path}/doc.txt').writeAsString('blueberry');
    await index.grant(directory, consent: true);
    index.revoke();
    expect((await retriever.retrieve('blueberry')).hits, isEmpty);
    final restarted = LocalSemanticRetriever(FileIndex());
    expect((await restarted.retrieve('blueberry')).status,
        LocalRetrievalStatus.disabled);
  });

  test('cancellation returns no partial citations', () async {
    await File('${directory.path}/doc.txt').writeAsString('blueberry');
    await index.grant(directory, consent: true);
    final result = await retriever.retrieve(
      'blueberry',
      isCancelled: () async => true,
    );
    expect(result.status, LocalRetrievalStatus.cancelled);
    expect(result.hits, isEmpty);
  });

  test('timeout returns no partial citations', () async {
    await File('${directory.path}/doc.txt').writeAsString('blueberry');
    await index.grant(directory, consent: true);
    final result =
        await retriever.retrieve('blueberry', timeout: Duration.zero);
    expect(result.status, LocalRetrievalStatus.invalidQuery);
  });

  test('deleted file disappears after refresh', () async {
    final file = File('${directory.path}/doc.txt');
    await file.writeAsString('blueberry');
    await index.grant(directory, consent: true);
    await file.delete();
    await index.refresh();
    expect((await retriever.retrieve('blueberry')).hits, isEmpty);
  });

  test('Hebrew text tokenization works without network', () async {
    await File('${directory.path}/hebrew.txt')
        .writeAsString('תפוח ירוק בגינה');
    await index.grant(directory, consent: true);
    expect((await retriever.retrieve('תפוח')).hits, isNotEmpty);
  });
}
