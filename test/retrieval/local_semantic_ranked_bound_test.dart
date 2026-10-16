import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/file_index.dart';
import 'package:local_bluey/services/local_semantic_retrieval.dart';

void main() {
  test('ac1 bounded ranking preserves grounded top citations', () async {
    final directory = await Directory.systemTemp.createTemp('ranked-files-');
    final index = FileIndex();
    try {
      final file = File('${directory.path}/document.txt');
      await file.writeAsString(List.filled(800, 'alpha').join(' '));
      await index.grant(directory, consent: true);

      final retriever = LocalSemanticRetriever(index);
      final full = await retriever.retrieve('alpha', limit: 50);
      final top = await retriever.retrieve('alpha', limit: 2);

      expect(full.status, LocalRetrievalStatus.ready);
      expect(top.status, LocalRetrievalStatus.ready);
      expect(top.hits, hasLength(2));
      expect(top.hits.map((hit) => hit.path), everyElement(file.path));
      expect(
        top.hits.map((hit) => hit.score).toList(),
        full.hits.take(2).map((hit) => hit.score).toList(),
      );
    } finally {
      index.revoke();
      await directory.delete(recursive: true);
    }
  });

  test('ac3 empty or disabled index emits no ranked citations', () async {
    final retriever = LocalSemanticRetriever(FileIndex());
    final result = await retriever.retrieve('alpha', limit: 2);
    expect(result.status, LocalRetrievalStatus.disabled);
    expect(result.hits, isEmpty);
  });
}
