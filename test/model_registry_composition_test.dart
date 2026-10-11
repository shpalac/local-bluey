import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:local_bluey/services/model_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory support;
  late Directory models;
  late File marker;
  late List<DataStoreInfo> originalStores;
  late DataStoreInfo realModel;
  late ModelStore owner;
  late ModelAsset asset;
  final leases = <ModelLease>[];
  var pathCalls = <String>[];
  var secureDeletes = 0;
  Completer<void>? siblingRelease;
  Future<void>? pendingDelete;

  ModelStore open() => ModelStore(
    root: models,
    acceptedFormats: {'synthetic'},
    acceptedBackends: {'synthetic'},
    freeSpace: () async => 100,
    downloader: (_, offset) async* {
      yield [1, 2, 3].sublist(offset);
    },
  );
  Future<ModelLease> acquire() async {
    final lease = (await owner.acquire())!;
    leases.add(lease);
    return lease;
  }

  setUp(() async {
    support = await Directory.systemTemp.createTemp(
      'model-registry-composition-',
    );
    models = Directory('${support.path}/models');
    marker = File('${support.path}/unrelated.synthetic')
      ..writeAsStringSync('untouched');
    originalStores = List.of(DataRegistry.stores);
    realModel = originalStores.singleWhere((s) => s.id == 'model_store');
    pathCalls = [];
    secureDeletes = 0;
    siblingRelease = null;
    pendingDelete = null;
    messenger.setMockMethodCallHandler(pathChannel, (call) async {
      pathCalls.add(call.method);
      return support.path;
    });
    messenger.setMockMethodCallHandler(secureChannel, (call) async {
      if (call.method == 'deleteAll') secureDeletes++;
      return null;
    });
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    asset = ModelAsset(
      id: 'synthetic',
      revision: '1',
      bytes: 3,
      sha256Hex: sha256.convert([1, 2, 3]).toString(),
      format: 'synthetic',
      backend: 'synthetic',
      licenseNotice: 'synthetic notice, not license qualification',
    );
    owner = open();
    expect(await owner.install(asset), ModelInstallResult.activated);
  });
  tearDown(() async {
    try {
      if (siblingRelease != null && !siblingRelease!.isCompleted) {
        siblingRelease!.complete();
      }
      if (pendingDelete != null) await pendingDelete;
      for (final lease in leases) {
        await lease.release();
      }
      leases.clear();
      owner.dispose();
    } finally {
      DataRegistry.stores
        ..clear()
        ..addAll(originalStores);
      SharedPreferences.setMockInitialValues({});
      messenger.setMockMethodCallHandler(pathChannel, null);
      messenger.setMockMethodCallHandler(secureChannel, null);
      await support.delete(recursive: true);
    }
  });

  test('exact category callback routes app-support clear through live leased owner', () async {
    final held = await acquire();
    await realModel.clear();
    expect(pathCalls, ['getApplicationSupportDirectory']);
    expect(await owner.activeAsset(), isNull);
    expect(File('${models.path}/selection.json').existsSync(), isFalse);
    expect(File(held.path).readAsBytesSync(), [1, 2, 3]);
    expect(marker.readAsStringSync(), 'untouched');
    expect(
      (await SharedPreferences.getInstance()).getBool('onboarding.done'),
      isTrue,
    );
    expect(secureDeletes, 0);
    await held.release();
    expect(File(held.path).existsSync(), isFalse);
    expect(await owner.install(asset), ModelInstallResult.activated);
    expect((await owner.activeAsset())!.key, asset.key);
    expect(marker.readAsStringSync(), 'untouched');
  });
  test('actual deleteAll logical model clear precedes sibling and global reset, lease bytes remain', () async {
    final held = await acquire();
    final entered = Completer<void>();
    siblingRelease = Completer<void>();
    DataRegistry.stores
      ..clear()
      ..addAll([
        realModel,
        DataStoreInfo(
          id: 'controlled_sibling',
          sourceFile: 'test-only',
          whatEn: 'synthetic',
          whatHe: 'synthetic',
          where: 'test-only',
          retentionEn: 'test-only',
          retentionHe: 'test-only',
          clear: () async {
            entered.complete();
            await siblingRelease!.future;
          },
        ),
      ]);
    pendingDelete = DataRegistry.deleteAll();
    await entered.future;
    expect(pathCalls, ['getApplicationSupportDirectory']);
    expect(await owner.activeAsset(), isNull);
    expect(File('${models.path}/selection.json').existsSync(), isFalse);
    expect(File(held.path).readAsBytesSync(), [1, 2, 3]);
    expect(
      (await SharedPreferences.getInstance()).getBool('onboarding.done'),
      isTrue,
    );
    expect(secureDeletes, 0);
    expect(marker.readAsStringSync(), 'untouched');
    siblingRelease!.complete();
    await pendingDelete;
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    expect(secureDeletes, 1);
    expect(File(held.path).readAsBytesSync(), [1, 2, 3]);
    await held.release();
    expect(File(held.path).existsSync(), isFalse);
    expect(marker.readAsStringSync(), 'untouched');
  });
  test('exact category callback with retired owner deletes disk via temporary owner', () async {
    owner.dispose();
    await realModel.clear();
    expect(pathCalls, ['getApplicationSupportDirectory']);
    expect(models.listSync(recursive: true).whereType<File>(), isEmpty);
    expect(marker.readAsStringSync(), 'untouched');
    owner = open(); // Temporary clear owner retired and frees exact folder.
    expect(await owner.activeAsset(), isNull);
    expect(await owner.install(asset), ModelInstallResult.activated);
    expect(secureDeletes, 0);
  });
}
