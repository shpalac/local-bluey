import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:local_bluey/services/file_index.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('blu028-index-');
    await File('${directory.path}/note.txt')
        .writeAsString('local retrieval content');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('ready retrieval snapshot is invalid after revoke', () async {
    final index = FileIndex();

    await index.grant(directory, consent: true);

    final snapshot = index.retrievalSnapshot();

    expect(snapshot.values, contains('local retrieval content'));
    expect(index.matchesRetrievalSnapshot(snapshot), isTrue);

    index.revoke();

    expect(index.documentCount, 0);
    expect(index.retrievalSnapshot(), isEmpty);
    expect(index.matchesRetrievalSnapshot(snapshot), isFalse);
  });
}
