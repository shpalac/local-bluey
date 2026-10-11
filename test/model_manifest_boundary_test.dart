import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/model_store.dart';

void main() {
  Map<String, dynamic> valid() => {
    'id': 'synthetic-model',
    'revision': 'synthetic-revision',
    'bytes': 3,
    'sha256': List.filled(64, 'a').join(),
    'format': 'synthetic-format',
    'backend': 'synthetic-backend',
    'licenseNotice': 'synthetic notice, not license qualification',
    'languages': ['en'],
  };
  ModelManifest manifest(Object? asset, {Object? version = 1}) =>
      ModelManifest.parse(
        jsonEncode({
          'version': version,
          'assets': [asset],
        }),
      );

  for (final key in [
    'id',
    'revision',
    'sha256',
    'format',
    'backend',
    'bytes',
  ]) {
    for (final wrong in [false, true]) {
      test(
        'actual asset and manifest reject $key ${wrong ? 'type' : 'absence'}',
        () {
          final row = valid();
          if (wrong) {
            row[key] = key == 'bytes' ? '3' : 3;
          } else {
            row.remove(key);
          }
          final message =
              'asset.$key must be ${key == 'bytes' ? 'an int' : 'a string'}';
          final failure = isA<FormatException>().having(
            (e) => e.message,
            'field message',
            message,
          );
          expect(() => ModelAsset.fromJson(row), throwsA(failure));
          expect(() => manifest(row), throwsA(failure));
        },
      );
    }
  }

  test('bytes validation precedes required string validation', () {
    final row = valid()
      ..remove('bytes')
      ..remove('id');
    expect(
      () => ModelAsset.fromJson(row),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'first field',
          'asset.bytes must be an int',
        ),
      ),
    );
  });

  for (final shape in <Object?>[
    null,
    7,
    'synthetic',
    [],
    [valid()],
  ]) {
    test('top-level ${jsonEncode(shape)} is FormatException', () {
      expect(
        () => ModelManifest.parse(jsonEncode(shape)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'shape',
            'manifest must be an object',
          ),
        ),
      );
    });
    test('asset ${jsonEncode(shape)} is TypeError at cast', () {
      expect(() => manifest(shape), throwsA(isA<TypeError>()));
    });
  }
  for (final value in <Object?>[null, 7, 'synthetic', {}]) {
    test('assets container ${jsonEncode(value)} is FormatException', () {
      expect(
        () => ModelManifest.parse(jsonEncode({'version': 1, 'assets': value})),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'assets shape',
            'manifest.assets missing',
          ),
        ),
      );
    });
  }
  test('absent assets is FormatException', () {
    expect(() => ModelManifest.parse('{"version":1}'), throwsFormatException);
  });
  test('numeric equal version double passes comparison then TypeError', () {
    expect(() => manifest(valid(), version: 1.0), throwsA(isA<TypeError>()));
  });
  test('version mismatch precedes bad assets shape', () {
    expect(
      () => ModelManifest.parse('{"version":"1","assets":7}'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'version',
          'unsupported manifest version: 1',
        ),
      ),
    );
  });

  for (final notice in <Object?>[null, 7, false, [], {}]) {
    test('nonstring license ${jsonEncode(notice)} defaults empty', () {
      final row = valid()..['licenseNotice'] = notice;
      expect(ModelAsset.fromJson(row).licenseNotice, '');
      expect(manifest(row).assets.single.licenseNotice, '');
    });
  }
  test('absent optional values default empty and extra values ignored', () {
    final row = valid()
      ..remove('licenseNotice')
      ..remove('languages')
      ..['extra'] = 'ignored';
    final asset = manifest(row).assets.single;
    expect(asset.licenseNotice, '');
    expect(asset.languages, isEmpty);
    expect(asset.id, 'synthetic-model');
    final source = jsonEncode({'version': 1, 'assets': [], 'extra': true});
    expect(ModelManifest.parse(source).assets, isEmpty);
  });
  for (final languages in <Object?>[null, 'en', 7, {}]) {
    test('nonlist languages ${jsonEncode(languages)} defaults empty', () {
      expect(
        manifest(valid()..['languages'] = languages).assets.single.languages,
        isEmpty,
      );
    });
  }
  test(
    'mixed languages keeps all string values without capability validation',
    () {
      final row = valid()
        ..['languages'] = [
          'en',
          7,
          null,
          '',
          'en',
          'synthetic-unqualified',
          false,
        ];
      expect(manifest(row).assets.single.languages, [
        'en',
        '',
        'en',
        'synthetic-unqualified',
      ]);
    },
  );

  final admission = <String, (Map<String, dynamic>, ModelInstallResult)>{
    'missing notice precedes invalid bytes and unsupported format': (
      {'licenseNotice': null, 'bytes': -1, 'format': 'other'},
      ModelInstallResult.missingLicense,
    ),
    'whitespace notice is parse accepted': (
      {'licenseNotice': '  '},
      ModelInstallResult.missingLicense,
    ),
    'zero bytes precedes incompatible backend': (
      {'bytes': 0, 'backend': 'other'},
      ModelInstallResult.invalidMetadata,
    ),
    'negative bytes is parse accepted': (
      {'bytes': -3},
      ModelInstallResult.invalidMetadata,
    ),
    'uppercase digest precedes incompatible format': (
      {'sha256': List.filled(64, 'A').join(), 'format': 'other'},
      ModelInstallResult.invalidMetadata,
    ),
    'short digest is parse accepted': (
      {'sha256': 'synthetic'},
      ModelInstallResult.invalidMetadata,
    ),
    'unknown format metadata': (
      {'format': 'other'},
      ModelInstallResult.incompatible,
    ),
    'unknown backend metadata': (
      {'backend': 'other'},
      ModelInstallResult.incompatible,
    ),
  };
  for (final item in admission.entries) {
    test('parse versus actual install: ${item.key}', () async {
      final row = valid()..addAll(item.value.$1);
      final asset = manifest(row).assets.single;
      expect(asset.bytes, row['bytes']);
      final root = await Directory.systemTemp.createTemp('manifest-boundary-');
      var spaceCalls = 0;
      var transfers = 0;
      final store = ModelStore(
        root: root,
        acceptedFormats: {'synthetic-format'},
        acceptedBackends: {'synthetic-backend'},
        freeSpace: () async {
          spaceCalls++;
          return 100;
        },
        downloader: (_, _) {
          transfers++;
          throw StateError('unexpected synthetic transfer');
        },
      );
      try {
        expect(await store.install(asset), item.value.$2);
        expect(spaceCalls, 0);
        expect(transfers, 0);
        expect(await store.activeAsset(), isNull);
        expect(root.listSync(), isEmpty);
      } finally {
        store.dispose();
        await root.delete(recursive: true);
      }
    });
  }
  test(
    'empty semantic strings are parse accepted, not validated asset identity',
    () {
      final row = valid()
        ..['id'] = ''
        ..['revision'] = ''
        ..['format'] = ''
        ..['backend'] = ''
        ..['sha256'] = '';
      final asset = manifest(row).assets.single;
      expect(asset.id, '');
      expect(asset.revision, '');
      expect(asset.format, '');
      expect(asset.backend, '');
      expect(asset.sha256Hex, '');
    },
  );
}
