import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/file_index.dart';
import 'package:local_bluey/services/local_semantic_retrieval.dart';

void main() {
  late Directory directory;
  late FileIndex index;
  late LocalSemanticRetriever retrieval;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bluey-final-check-');
    await File('${directory.path}/note.txt')
        .writeAsString('blueberry local semantic retrieval');
    index = FileIndex();
    await index.grant(directory, consent: true);
    retrieval = LocalSemanticRetriever(index);
  });

  tearDown(() async {
    index.revoke();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('late cancellation returns no ranked citations', () async {
    var cancellationChecks = 0;
    final result = await retrieval.retrieve(
      'blueberry',
      isCancelled: () async => ++cancellationChecks == 2,
    );

    expect(cancellationChecks, 2);
    expect(result.status, LocalRetrievalStatus.cancelled);
    expect(result.hits, isEmpty);
  });

  test('final permission revocation returns no ranked citations', () async {
    var cancellationChecks = 0;
    final result = await retrieval.retrieve(
      'blueberry',
      isCancelled: () async {
        cancellationChecks++;
        if (cancellationChecks == 2) index.revoke();
        return false;
      },
    );

    expect(cancellationChecks, 2);
    expect(result.status, LocalRetrievalStatus.cancelled);
    expect(result.hits, isEmpty);
  });
}
