import 'dart:async';
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

  group('concurrency and lease safety', () {
    test('deleteAll during a gated install is not undone by it', () async {
      final gate = Completer<void>();
      final s = store(
        source: (a, offset) async* {
          await gate.future;
          yield bytes.sublist(offset);
        },
      );
      final install = s.install(asset);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await s.deleteAll();
      gate.complete();
      expect(await install, ModelInstallResult.cancelled);
      expect(await s.activeAsset(), isNull);
      expect(
        Directory('${dir.path}/assets').listSync().whereType<File>(),
        isEmpty,
      );
      expect(File('${dir.path}/selection.json').existsSync(), isFalse);
    });

    test('removeActive during a gated install of another asset wins', () async {
      final s = store();
      expect(await s.install(asset), ModelInstallResult.activated);
      final other = List<int>.generate(200, (i) => (i * 7) % 251);
      final gate = Completer<void>();
      final slow = store(
        source: (a, offset) async* {
          await gate.future;
          yield other.sublist(offset);
        },
      );
      final install = slow.install(make(other, rev: '2'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await slow.removeActive();
      gate.complete();
      expect(await install, ModelInstallResult.cancelled);
      expect(await slow.activeAsset(), isNull);
    });

    test('acquire is atomic with a concurrent removeActive', () async {
      final s = store();
      await s.install(asset);
      final lease = s.acquire();
      final removal = s.removeActive();
      final held = await lease;
      await removal;
      // Lease was registered before the removal ran, so the file stays.
      expect(held, isNotNull);
      expect(File(held!.path).existsSync(), isTrue);
      await held.release();
      expect(File(held.path).existsSync(), isFalse);
    });

    test('same id and revision with a new digest keeps leased bytes', () async {
      final changed = List<int>.generate(300, (i) => (i * 3) % 251);
      final other = make(changed);
      final s = store(
        source: (a, offset) async* {
          yield (a.sha256Hex == other.sha256Hex ? changed : bytes).sublist(
            offset,
          );
        },
      );
      final s2 = s;
      await s.install(asset);
      final lease = (await s.acquire())!;
      expect(await s2.install(other), ModelInstallResult.activated);
      expect(lease.path, isNot('${dir.path}/assets/${other.fileName}'));
      expect(File(lease.path).readAsBytesSync(), bytes);
      await lease.release();
      expect(File(lease.path).existsSync(), isFalse);
      final fresh = (await s2.acquire())!;
      expect(File(fresh.path).readAsBytesSync(), changed);
      await fresh.release();
    });

    test('keys do not collide for a/b versus a_b', () {
      final x = make(bytes, id: 'a/b');
      final y = make(bytes, id: 'a_b');
      expect(x.key, isNot(y.key));
      expect(x.fileName, isNot(y.fileName));
      expect(make(bytes, id: '../x').fileName.contains('/'), isFalse);
    });

    test(
      'colliding-looking ids install side by side without overwrite',
      () async {
        final b1 = List<int>.generate(120, (i) => i % 200);
        final b2 = List<int>.generate(150, (i) => (i + 9) % 200);
        final x = make(b1, id: 'a/b');
        final y = make(b2, id: 'a_b');
        final s = store(files: {x.key: b1, y.key: b2});
        expect(await s.install(x), ModelInstallResult.activated);
        final lease = (await s.acquire())!;
        expect(await s.install(y), ModelInstallResult.activated);
        expect(File(lease.path).readAsBytesSync(), b1);
        await lease.release();
      },
    );

    test(
      'registry clear goes through the live store and honors leases',
      () async {
        final support = Directory('${dir.path}/support')..createSync();
        final models = Directory('${support.path}/models')..createSync();
        final live = ModelStore(
          root: models,
          acceptedFormats: const {'gguf'},
          acceptedBackends: const {'fake'},
          freeSpace: () async => free,
          downloader: (a, offset) async* {
            yield bytes.sublist(offset);
          },
        );
        expect(await live.install(asset), ModelInstallResult.activated);
        final lease = (await live.acquire())!;
        await ModelStore.clearOnDisk(supportDir: support);
        expect(await live.activeAsset(), isNull);
        expect(File(lease.path).existsSync(), isTrue);
        await lease.release();
        expect(File(lease.path).existsSync(), isFalse);
        live.dispose();
      },
    );

    test(
      'registry clear without a live store deletes the folder files',
      () async {
        final support = Directory('${dir.path}/support2')..createSync();
        final models = Directory('${support.path}/models')..createSync();
        final temp = ModelStore(
          root: models,
          acceptedFormats: const {'gguf'},
          acceptedBackends: const {'fake'},
          freeSpace: () async => free,
          downloader: (a, offset) async* {
            yield bytes.sublist(offset);
          },
        );
        await temp.install(asset);
        temp.dispose();
        await ModelStore.clearOnDisk(supportDir: support);
        expect(models.listSync(recursive: true).whereType<File>(), isEmpty);
      },
    );
  });
}
