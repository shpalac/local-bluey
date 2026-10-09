import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:local_bluey/services/model_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late List<int> bytes;
  late ModelAsset asset;
  var free = 1 << 30;
  var served = <int>[];

  ModelAsset make(
    List<int> data, {
    String id = 'fixture',
    String rev = '1',
    String? sha,
    int? size,
    String format = 'gguf',
    String backend = 'fake',
    String license = 'MIT test fixture',
  }) => ModelAsset(
    id: id,
    revision: rev,
    bytes: size ?? data.length,
    sha256Hex: sha ?? sha256.convert(data).toString(),
    format: format,
    backend: backend,
    licenseNotice: license,
  );

  ModelStore store({
    Stream<List<int>> Function(ModelAsset, int)? source,
    Map<String, List<int>>? files,
  }) => ModelStore(
    root: dir,
    acceptedFormats: const {'gguf'},
    acceptedBackends: const {'fake'},
    freeSpace: () async => free,
    downloader:
        source ??
        (a, offset) async* {
          final data = (files ?? {a.key: bytes})[a.key]!;
          served.add(offset);
          yield data.sublist(offset);
        },
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('model_store_test');
    bytes = List.generate(300, (i) => i % 251);
    asset = make(bytes);
    free = 1 << 30;
    served = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('manifest', () {
    test('parses the supported version', () {
      final m = ModelManifest.parse(
        jsonEncode({
          'version': 1,
          'assets': [
            {
              'id': 'a',
              'revision': '1',
              'bytes': 3,
              'sha256': 'x',
              'format': 'gguf',
              'backend': 'fake',
              'licenseNotice': 'MIT',
              'languages': ['en'],
            },
          ],
        }),
      );
      expect(m.assets.single.languages, ['en']);
    });

    test('unknown version throws', () {
      expect(
        () => ModelManifest.parse('{"version": 2, "assets": []}'),
        throwsFormatException,
      );
    });
  });

  group('install validation, nothing activates on failure', () {
    Future<void> expectFail(
      ModelAsset a,
      ModelInstallResult want, {
      List<int>? data,
    }) async {
      final s = store(files: {a.key: data ?? bytes});
      expect(await s.install(a), want);
      expect(await s.activeAsset(), isNull);
      expect(File('${dir.path}/selection.json').existsSync(), isFalse);
    }

    test('wrong hash', () async {
      await expectFail(
        make(bytes, sha: '0' * 64),
        ModelInstallResult.hashMismatch,
      );
    });

    test('wrong size (longer than declared)', () async {
      await expectFail(make(bytes, size: 10), ModelInstallResult.wrongSize);
    });

    test('incompatible format and backend', () async {
      await expectFail(
        make(bytes, format: 'onnx'),
        ModelInstallResult.incompatible,
      );
      await expectFail(
        make(bytes, backend: 'other'),
        ModelInstallResult.incompatible,
      );
    });

    test('missing license', () async {
      await expectFail(
        make(bytes, license: '  '),
        ModelInstallResult.missingLicense,
      );
    });

    test('bad digest format', () async {
      await expectFail(
        make(bytes, sha: 'abc'),
        ModelInstallResult.invalidMetadata,
      );
    });

    test('insufficient space does not even start a transfer', () async {
      free = 10;
      final s = store();
      expect(await s.install(asset), ModelInstallResult.insufficientSpace);
      expect(served, isEmpty);
      expect(await s.activeAsset(), isNull);
    });
  });

  group('transfer', () {
    test('verified install activates and persists across restart', () async {
      expect(await store().install(asset), ModelInstallResult.activated);
      final restarted = store();
      expect((await restarted.activeAsset())!.key, asset.key);
      expect(await restarted.install(asset), ModelInstallResult.alreadyActive);
    });

    test('interrupted transfer keeps nothing active and resumes', () async {
      final s = store(
        source: (a, offset) async* {
          yield bytes.sublist(offset, 100);
          throw const SocketException('lost');
        },
      );
      expect(await s.install(asset), ModelInstallResult.interrupted);
      expect(await s.activeAsset(), isNull);
      final resumed = store();
      expect(await resumed.install(asset), ModelInstallResult.activated);
      expect(served, [100]);
    });

    test('cancel leaves no half-activated asset', () async {
      final token = ModelCancelToken();
      final s = store(
        source: (a, offset) async* {
          token.cancel();
          yield bytes;
        },
      );
      expect(
        await s.install(asset, cancel: token),
        ModelInstallResult.cancelled,
      );
      expect(await s.activeAsset(), isNull);
      expect(Directory('${dir.path}/assets').listSync(), isEmpty);
    });

    test('failed update keeps the previous verified selection', () async {
      final s = store();
      await s.install(asset);
      final other = List.generate(200, (i) => (i * 7) % 251);
      final bad = make(other, rev: '2', sha: '1' * 64);
      final s2 = store(files: {bad.key: other});
      expect(await s2.install(bad), ModelInstallResult.hashMismatch);
      expect((await s2.activeAsset())!.revision, '1');
      expect(Directory('${dir.path}/partial').listSync(), isEmpty);
    });

    test('switching to a verified revision replaces the old files', () async {
      final s = store();
      await s.install(asset);
      final other = List.generate(200, (i) => (i * 7) % 251);
      final next = make(other, rev: '2');
      final s2 = store(files: {next.key: other});
      expect(await s2.install(next), ModelInstallResult.activated);
      expect((await s2.activeAsset())!.revision, '2');
      expect(Directory('${dir.path}/assets').listSync().length, 1);
    });
  });

  group('leases', () {
    test('switch while leased keeps the file until release', () async {
      final other = List.generate(200, (i) => (i * 7) % 251);
      final next = make(other, rev: '2');
      final s = store(files: {asset.key: bytes, next.key: other});
      await s.install(asset);
      final lease = (await s.acquire())!;
      await s.install(next);
      expect((await s.activeAsset())!.revision, '2');
      expect(File(lease.path).existsSync(), isTrue);
      await lease.release();
      expect(File(lease.path).existsSync(), isFalse);
    });

    test('remove while leased clears selection now, file on release', () async {
      final s = store();
      await s.install(asset);
      final lease = (await s.acquire())!;
      await s.removeActive();
      expect(await s.activeAsset(), isNull);
      expect(File(lease.path).existsSync(), isTrue);
      await lease.release();
      await lease.release();
      expect(File(lease.path).existsSync(), isFalse);
    });

    test('acquire without an active asset returns null', () async {
      expect(await store().acquire(), isNull);
    });
  });

  group('delete all', () {
    test(
      'removes selection, files and partials without resurrection',
      () async {
        final s = store();
        await s.install(asset);
        File('${dir.path}/partial/x.part')
          ..createSync(recursive: true)
          ..writeAsBytesSync([1, 2, 3]);
        expect((await s.inventory())['partialBytes'], 3);
        await s.deleteAll();
        expect(await s.activeAsset(), isNull);
        expect(await store().activeAsset(), isNull);
        expect(await s.inventory(), {'partialBytes': 0});
        expect(Directory('${dir.path}/assets').listSync(), isEmpty);
      },
    );

    test('delete all with a lease waits for release', () async {
      final s = store();
      await s.install(asset);
      final lease = (await s.acquire())!;
      await s.deleteAll();
      expect(await s.activeAsset(), isNull);
      expect(File(lease.path).existsSync(), isTrue);
      await lease.release();
      expect(File(lease.path).existsSync(), isFalse);
    });
  });

  test('registry lists the model store with honest retention', () {
    final info = DataRegistry.stores.firstWhere((s) => s.id == 'model_store');
    expect(info.retentionEn, contains('nothing is downloaded unasked'));
    expect(info.sourceFile, 'lib/services/model_store.dart');
  });

  test('registry clear is a no-op without a platform folder', () async {
    await DataRegistry.stores.firstWhere((s) => s.id == 'model_store').clear();
  });
}
