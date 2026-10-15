import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/file_index.dart';

void main() {
  late Directory directory;
  late FileIndex index;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bluey-grant-');
    index = FileIndex();
    await File('${directory.path}/visible.txt').writeAsString('needle');
  });

  tearDown(() async {
    index.revoke();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('ac1 denied replacement grant purges old indexed content', () async {
    await index.grant(directory, consent: true);
    expect(index.documentCount, 1);

    await index.grant(directory, consent: false);

    expect(index.state, FileIndexState.denied);
    expect(index.isEnabled, isFalse);
    expect(index.documentCount, 0);
    expect(index.retrievalSnapshot(), isEmpty);
    expect(index.search('needle'), isEmpty);
  });

  test('ac2 invalid replacement cannot retain previous documents', () async {
    await index.grant(directory, consent: true);
    expect(index.documentCount, 1);

    await expectLater(
      index.grant(Directory('${directory.path}/missing'), consent: true),
      throwsA(isA<FileSystemException>()),
    );

    expect(index.state, FileIndexState.failed);
    expect(index.isEnabled, isFalse);
    expect(index.documentCount, 0);
    expect(index.retrievalSnapshot(), isEmpty);
  });

  test('ac2 revoke during pending grant cannot restore indexing', () async {
    final pending = index.grant(directory, consent: true);
    index.revoke();
    await pending;

    expect(index.state, FileIndexState.disabled);
    expect(index.isEnabled, isFalse);
    expect(index.documentCount, 0);
    expect(index.search('needle'), isEmpty);
  });
}
