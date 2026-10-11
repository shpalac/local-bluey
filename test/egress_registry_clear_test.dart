import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:local_bluey/services/egress_monitor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final monitor = EgressMonitor.instance;
  late Directory documents;
  late File egressFile;
  late File marker;
  late List<DataStoreInfo> stores;
  late DataStoreInfo realEgress;
  Completer<void>? pathEntered;
  Completer<void>? pathRelease;
  var secureDeletes = 0;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('egress-registry-');
    egressFile = File('${documents.path}/egress.jsonl');
    marker = File('${documents.path}/unrelated.synthetic');
    stores = List.of(DataRegistry.stores);
    realEgress = stores.singleWhere((store) => store.id == 'egress');
    pathEntered = null;
    pathRelease = null;
    secureDeletes = 0;
    messenger.setMockMethodCallHandler(pathChannel, (call) async {
      if (pathEntered != null && !pathEntered!.isCompleted) {
        pathEntered!.complete();
        await pathRelease!.future;
      }
      return documents.path;
    });
    messenger.setMockMethodCallHandler(secureChannel, (call) async {
      if (call.method == 'deleteAll') secureDeletes++;
      return null;
    });
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    await monitor.clear();
    await marker.writeAsString('unrelated synthetic marker');
  });

  tearDown(() async {
    if (pathRelease != null && !pathRelease!.isCompleted) {
      pathRelease!.complete();
    }
    await monitor.load(); // Drain older singleton work before final deletion.
    await monitor.clear();
    DataRegistry.stores
      ..clear()
      ..addAll(stores);
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(secureChannel, null);
    messenger.setMockMethodCallHandler(pathChannel, null);
    await documents.delete(recursive: true);
  });

  DataStoreInfo sibling(Future<void> Function() clear) => DataStoreInfo(
    id: 'controlled_sibling',
    sourceFile: 'test-only',
    whatEn: 'synthetic',
    whatHe: 'synthetic',
    where: 'test-only',
    retentionEn: 'test-only',
    retentionHe: 'test-only',
    clear: clear,
  );

  test(
    'actual category clear waits for entered old file write; fresh survives',
    () async {
      await monitor.record('http://localhost/seed', 'seed', 1);
      expect(await egressFile.exists(), isTrue);
      pathEntered = Completer<void>();
      pathRelease = Completer<void>();
      final recording = monitor.record(
        'https://old.synthetic.example/path',
        'old',
        2,
      );
      await pathEntered!
          .future; // Actual private file storage entered path lookup.
      expect(monitor.entries.map((entry) => entry.kind), ['seed', 'old']);
      var clearFinished = false;
      final clearing = realEgress.clear().then((_) => clearFinished = true);
      expect(clearFinished, isFalse);
      expect(await egressFile.readAsString(), contains('seed'));
      pathRelease!.complete();
      await Future.wait([recording, clearing]);
      await monitor.load();
      expect(clearFinished, isTrue);
      expect(monitor.entries, isEmpty);
      expect(monitor.historyAvailable, isTrue);
      expect(await egressFile.exists(), isFalse);
      expect(await marker.readAsString(), 'unrelated synthetic marker');
      await monitor.record('http://localhost/fresh', 'fresh', 3);
      expect(monitor.entries.single.kind, 'fresh');
      final saved = await egressFile.readAsString();
      expect(saved, contains('fresh'));
      expect(saved, isNot(contains('old.synthetic.example')));
      expect(await marker.exists(), isTrue);
    },
  );

  test(
    'actual deleteAll clears real egress before sibling and global reset',
    () async {
      await monitor.record('https://retained.synthetic.example', 'retained', 4);
      final siblingEntered = Completer<void>();
      final siblingRelease = Completer<void>();
      addTearDown(() {
        if (!siblingRelease.isCompleted) siblingRelease.complete();
      });
      DataRegistry.stores
        ..clear()
        ..addAll([
          realEgress, // Exact existing entry/callback, not a replacement.
          sibling(() async {
            siblingEntered.complete();
            await siblingRelease.future;
          }),
        ]);
      final deleting = DataRegistry.deleteAll();
      await siblingEntered.future;
      expect(monitor.entries, isEmpty);
      expect(await egressFile.exists(), isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool('onboarding.done'),
        isTrue,
      );
      expect(secureDeletes, 0);
      expect(await marker.exists(), isTrue);
      siblingRelease.complete();
      await deleting;
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect(secureDeletes, 1);
      expect(await marker.readAsString(), 'unrelated synthetic marker');
      await monitor.record('http://localhost/after-reset', 'after-reset', 0);
      expect(monitor.entries.single.kind, 'after-reset');
      expect(await egressFile.readAsString(), contains('after-reset'));
    },
  );

  test(
    'sibling failure preserves reset intent after actual egress deletion',
    () async {
      await monitor.record('https://retained.synthetic.example', 'retained', 5);
      DataRegistry.stores
        ..clear()
        ..addAll([
          realEgress,
          sibling(() async => throw StateError('controlled sibling failure')),
        ]);
      await expectLater(
        DataRegistry.deleteAll(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'store id',
            contains('controlled_sibling'),
          ),
        ),
      );
      expect(monitor.entries, isEmpty);
      expect(await egressFile.exists(), isFalse);
      expect(monitor.historyAvailable, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool('onboarding.done'),
        isTrue,
      );
      expect(secureDeletes, 0);
      expect(await marker.exists(), isTrue);
      // This is a controlled sibling failure, not invented filesystem failure.
      DataRegistry.stores
        ..clear()
        ..add(realEgress);
      await DataRegistry.deleteAll();
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect(secureDeletes, 1);
    },
  );
}
