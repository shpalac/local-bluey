import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/model_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ModelStore store;
  final leases = <ModelLease>[];
  final data = <String, List<int>>{};

  ModelAsset asset(String revision, List<int> bytes) {
    final result = ModelAsset(
      id: 'synthetic',
      revision: revision,
      bytes: bytes.length,
      sha256Hex: sha256.convert(bytes).toString(),
      format: 'synthetic',
      backend: 'synthetic',
      licenseNotice: 'synthetic notice, not license qualification',
    );
    data[result.key] = bytes;
    return result;
  }

  int diskBytes(String folder) {
    final dir = Directory('${root.path}/$folder');
    return dir.existsSync()
        ? dir.listSync().whereType<File>().fold(0, (n, f) => n + f.lengthSync())
        : 0;
  }

  Future<ModelLease> acquire() async {
    final lease = (await store.acquire())!;
    leases.add(lease);
    return lease;
  }

  Map<String, Object> active(ModelAsset a, {int partial = 0}) => {
    'active': '${a.id}@${a.revision}',
    'activeBytes': a.bytes,
    'partialBytes': partial,
  };

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'model-inventory-characterization-',
    );
    data.clear();
    store = ModelStore(
      root: root,
      acceptedFormats: {'synthetic'},
      acceptedBackends: {'synthetic'},
      freeSpace: () async => 100,
      downloader: (a, offset) async* {
        yield data[a.key]!.sublist(offset);
      },
    );
  });
  tearDown(() async {
    try {
      for (final lease in leases) {
        await lease.release();
      }
      leases.clear();
      store.dispose();
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('empty inventory has partial zero, not an empty map', () async {
    expect(await store.inventory(), {'partialBytes': 0});
    expect(root.listSync(), isEmpty);
  });
  test(
    'active count is declared asset size, not selection metadata bytes',
    () async {
      final a = asset('1', [1, 2, 3]);
      expect(await store.install(a), ModelInstallResult.activated);
      expect(await store.inventory(), active(a));
      expect(diskBytes('assets'), 3);
      expect(File('${root.path}/selection.json').lengthSync(), greaterThan(3));
    },
  );
  test(
    'switch excludes old leased bytes although both files are retained',
    () async {
      final a = asset('1', [1, 2, 3]);
      final b = asset('2', [4, 5, 6, 7, 8]);
      expect(await store.install(a), ModelInstallResult.activated);
      final held = await acquire();
      expect(await store.install(b), ModelInstallResult.activated);
      expect(File(held.path).readAsBytesSync(), [1, 2, 3]);
      expect(diskBytes('assets'), 8);
      expect(await store.inventory(), active(b));
      await held.release();
      expect(diskBytes('assets'), 5);
      expect(await store.inventory(), active(b));
    },
  );
  test(
    'remove excludes pending leased bytes until final release deletes them',
    () async {
      final a = asset('1', [1, 2, 3]);
      expect(await store.install(a), ModelInstallResult.activated);
      final held = await acquire();
      await store.removeActive();
      expect(await store.inventory(), {'partialBytes': 0});
      expect(diskBytes('assets'), 3);
      expect(File(held.path).readAsBytesSync(), [1, 2, 3]);
      await held.release();
      expect(diskBytes('assets'), 0);
      expect(await store.inventory(), {'partialBytes': 0});
    },
  );
  test(
    'orphan assets excluded, partial files counted, nested files not counted',
    () async {
      final a = asset('1', [1, 2, 3]);
      expect(await store.install(a), ModelInstallResult.activated);
      File('${root.path}/assets/synthetic-orphan')
          .writeAsBytesSync([7, 8, 9, 10]);
      File('${root.path}/partial/one.part').writeAsBytesSync([1, 2]);
      File('${root.path}/partial/two.part').writeAsBytesSync([3, 4, 5]);
      final nested = Directory('${root.path}/partial/nested')..createSync();
      File('${nested.path}/excluded.part').writeAsBytesSync([1, 2, 3, 4]);
      expect(diskBytes('assets'), 7);
      expect(diskBytes('partial'), 5);
      expect(await store.inventory(), active(a, partial: 5));
      await store.deleteAll();
      expect(await store.inventory(), {'partialBytes': 0});
      expect(diskBytes('assets'), 0);
      expect(Directory('${root.path}/partial').existsSync(), isFalse);
    },
  );
}
