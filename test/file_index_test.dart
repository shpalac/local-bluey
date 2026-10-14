import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/file_index.dart';

void main() {
  late Directory root;
  late FileIndex index;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bluey-index-');
    index = FileIndex();
  });

  tearDown(() async {
    index.revoke();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('explicit consent only; revoke purges all matches', () async {
    await File('${root.path}/allowed.txt').writeAsString('needle');
    await index.grant(root, consent: false);
    expect(index.documentCount, 0);
    await index.grant(root, consent: true);
    expect(index.search('needle'), hasLength(1));
    index.revoke();
    expect(index.search('needle'), isEmpty);
  });

  test('hidden files and folders excluded', () async {
    await File('${root.path}/.secret').writeAsString('needle');
    await Directory('${root.path}/.private').create();
    await File('${root.path}/.private/secret.txt').writeAsString('needle');
    await File('${root.path}/public.txt').writeAsString('visible');
    await index.grant(root, consent: true);
    expect(index.documentCount, 1);
    expect(index.search('needle'), isEmpty);
  });

  test('incremental edits and deletions', () async {
    final file = File('${root.path}/doc.txt');
    await file.writeAsString('old');
    await index.grant(root, consent: true);
    expect(index.search('old'), hasLength(1));
    await file.writeAsString('new words that change size');
    await index.refresh();
    expect(index.search('old'), isEmpty);
    expect(index.search('new'), hasLength(1));
    await file.delete();
    await index.refresh();
    expect(index.documentCount, 0);
  });

  test('invalid directory does not enable access', () async {
    await expectLater(
      index.grant(Directory('${root.path}/missing'), consent: true),
      throwsFileSystemException,
    );
    expect(index.isEnabled, isFalse);
  });

  test('restart has no durable grant', () async {
    await File('${root.path}/doc.txt').writeAsString('needle');
    await index.grant(root, consent: true);
    final nextProcess = FileIndex();
    expect(nextProcess.isEnabled, isFalse);
    expect(nextProcess.search('needle'), isEmpty);
  });

  test('oversized files are excluded', () async {
    await File('${root.path}/large.txt').writeAsString('needle');
    index = FileIndex(maxBytes: 3);
    await index.grant(root, consent: true);
    expect(index.documentCount, 0);
  });
}
