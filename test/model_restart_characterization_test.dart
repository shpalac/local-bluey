import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/model_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ModelStore owner;
  late ModelAsset asset;
  late List<int> original;
  final leases = <ModelLease>[];
  var transfers = 0;
  var spaceCalls = 0;

  ModelStore open({bool accepts = true}) => ModelStore(
    root: root,
    acceptedFormats: accepts ? {'synthetic'} : {},
    acceptedBackends: accepts ? {'synthetic'} : {},
    freeSpace: () async {
      spaceCalls++;
      return 100;
    },
    downloader: (_, offset) async* {
      transfers++;
      yield original.sublist(offset);
    },
  );
  File retained() => File('${root.path}/assets/${asset.fileName}');
  File selection() => File('${root.path}/selection.json');
  void restart({bool accepts = true}) {
    owner.dispose();
    owner = open(accepts: accepts);
    transfers = 0;
    spaceCalls = 0;
  }

  Future<ModelLease> acquire() async {
    final lease = (await owner.acquire())!;
    leases.add(lease);
    return lease;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'model-restart-characterization-',
    );
    original = [1, 2, 3, 4, 5];
    asset = ModelAsset(
      id: 'synthetic',
      revision: '1',
      bytes: original.length,
      sha256Hex: sha256.convert(original).toString(),
      format: 'synthetic',
      backend: 'synthetic',
      licenseNotice: 'synthetic notice, not license qualification',
    );
    transfers = 0;
    spaceCalls = 0;
    owner = open();
    expect(await owner.install(asset), ModelInstallResult.activated);
    expect(retained().readAsBytesSync(), original);
    expect(transfers, 1);
    restart();
  });
  tearDown(() async {
    try {
      for (final lease in leases) {
        await lease.release();
      }
      leases.clear();
      owner.dispose();
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'same-size external mutation remains selectable and leasable, not rehashed',
    () async {
      final changed = [5, 4, 3, 2, 1];
      retained().writeAsBytesSync(changed, flush: true);
      restart();
      expect(sha256.convert(changed).toString(), isNot(asset.sha256Hex));
      final active = (await owner.activeAsset())!;
      expect(active.sha256Hex, asset.sha256Hex);
      expect(active.bytes, changed.length);
      final lease = await acquire();
      expect(File(lease.path).readAsBytesSync(), changed);
      expect(await owner.install(asset), ModelInstallResult.alreadyActive);
      expect(transfers, 0);
      expect(spaceCalls, 0);
    },
  );
  for (final missing in [false, true]) {
    test(
      '${missing ? 'missing' : 'wrong-size'} retained file prevents selection and lease without repair',
      () async {
        if (missing) {
          retained().deleteSync();
        } else {
          retained().writeAsBytesSync([1, 2], flush: true);
        }
        final before = selection().readAsStringSync();
        restart();
        expect(await owner.activeAsset(), isNull);
        expect(await owner.acquire(), isNull);
        expect(selection().readAsStringSync(), before);
        expect(retained().existsSync(), !missing);
        if (!missing) expect(retained().readAsBytesSync(), [1, 2]);
        expect(transfers, 0);
        expect(spaceCalls, 0);
      },
    );
  }
  final invalid = <String, String>{
    'malformed JSON': '{',
    'non-map JSON': '[]',
    'required field absence': '{"bytes":5}',
    'required field type': '{"bytes":"5"}',
  };
  for (final item in invalid.entries) {
    test(
      'restart ${item.key} returns null without deleting retained bytes',
      () async {
        selection().writeAsStringSync(item.value, flush: true);
        restart();
        expect(await owner.activeAsset(), isNull);
        expect(await owner.acquire(), isNull);
        expect(selection().readAsStringSync(), item.value);
        expect(retained().readAsBytesSync(), original);
        expect(transfers, 0);
        expect(spaceCalls, 0);
      },
    );
  }
  test('restart accepts blank notice and unsupported labels unlike install admission', () async {
    final json =
        jsonDecode(selection().readAsStringSync()) as Map<String, dynamic>;
    json['licenseNotice'] = '';
    json['format'] = 'unaccepted';
    json['backend'] = 'unaccepted';
    selection().writeAsStringSync(jsonEncode(json), flush: true);
    restart(accepts: false);
    final active = (await owner.activeAsset())!;
    expect(active.licenseNotice, '');
    expect(active.format, 'unaccepted');
    expect(active.backend, 'unaccepted');
    final lease = await acquire();
    expect(File(lease.path).readAsBytesSync(), original);
    expect(await owner.install(active), ModelInstallResult.missingLicense);
    expect(transfers, 0);
    expect(spaceCalls, 0);
  });
}
