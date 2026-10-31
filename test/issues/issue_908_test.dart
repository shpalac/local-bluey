import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _vendorRoot = 'third_party/flutter_secure_storage_linux';
const _trustedPristineHashes = <String, String>{
  'CHANGELOG.md':
      '25cc02aebb6a6ada5fd02caa0c4a5f762a18d501d8876da852172a522cd87e0b',
  'LICENSE': '55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa',
  'README.md':
      '0ce3496c8d934101e4dc17c2b0f5f8fb2fb9378b59d874791493fe414839cadc',
  'linux/CMakeLists.txt':
      '80a5ea0586fb5ccf8736c0cb3a6137def5b2ee4003e813236aa8b8975214effd',
  'linux/flutter_secure_storage_linux_plugin.cc':
      '980c4f2f285053351c52ecde59e4488d18b56b17c9a69a606b60ce03e15fa4fb',
  'linux/include/FHashTable.hpp':
      '095b00466e6650a2e93bd4b26f71c1d3eb740c99d668743635349e88a2b62c79',
  'linux/include/Secret.hpp':
      'e4585b9ec0d101ddd9fe38781f4ca25b1c69469463b1d8b9f555a27c87d89b77',
  'linux/include/flutter_secure_storage_linux/flutter_secure_storage_linux_plugin.h':
      '0cb236c60cb7b421ffd658d0cc0b6ee9c6c9aece9d269dad21dfbe2351314543',
  'pubspec.yaml':
      '28a8b1d4cd452c4391dbeda4438cc082d96bb28e32e0bb2006460018139b72dd',
};
const _patchedJsonHash =
    'd99a246165e67ac370a6393095ae10c8170e1a62f181a4c17d1c1e22d6245877';
const _originalJsonHash =
    '0d8d3e680a119c7c4e5ab45a95bc4dbd47474f69d57c7f89eab75c7d3ad3403a';

String _hashBytes(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  test('vendored linux storage tree matches trusted pristine hashes', () {
    final root = Directory(_vendorRoot);
    expect(root.existsSync(), isTrue);
    final actualFiles =
        root
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map(
              (file) => file.path
                  .substring(root.path.length + 1)
                  .replaceAll('\\', '/'),
            )
            .where((path) => path != 'linux/include/json.hpp')
            .toList()
          ..sort();
    final expectedFiles = _trustedPristineHashes.keys.toList()..sort();
    expect(
      actualFiles,
      expectedFiles,
      reason: 'Vendored file inventory must match pristine package exactly.',
    );
    for (final path in expectedFiles) {
      expect(
        _hashBytes(File('$_vendorRoot/$path').readAsBytesSync()),
        _trustedPristineHashes[path],
        reason: 'Unexpected vendor modification: $path',
      );
    }
    expect(File('$_vendorRoot/LICENSE').existsSync(), isTrue);
    expect(
      File('docs/vendor/flutter-secure-storage-linux-1.2.3.md').existsSync(),
      isTrue,
    );
    expect(
      File('docs/vendor/flutter-secure-storage-linux-923.patch').existsSync(),
      isTrue,
    );
  });

  test('vendored json.hpp matches recorded patched hash and four-line diff', () {
    final bytes = File('$_vendorRoot/linux/include/json.hpp').readAsBytesSync();
    expect(_hashBytes(bytes), _patchedJsonHash);
    final patched = utf8.decode(bytes);
    const substitutions = <String, String>{
      'inline nlohmann::json operator ""_json(const char* s, std::size_t n)': 'inline nlohmann::json operator "" _json(const char* s, std::size_t n)',
      'inline nlohmann::json::json_pointer operator ""_json_pointer(const char* s, std::size_t n)': 'inline nlohmann::json::json_pointer operator "" _json_pointer(const char* s, std::size_t n)',
      '    using nlohmann::literals::json_literals::operator ""_json;':
          '    using nlohmann::literals::json_literals::operator "" _json;',
      '    using nlohmann::literals::json_literals::operator ""_json_pointer;': '    using nlohmann::literals::json_literals::operator "" _json_pointer;',
    };
    var original = patched;
    for (final entry in substitutions.entries) {
      expect(
        entry.key.allMatches(original).length,
        1,
        reason: 'Each upstream PR #923 replacement must occur exactly once',
      );
      original = original.replaceFirst(entry.key, entry.value);
    }
    expect(_hashBytes(utf8.encode(original)), _originalJsonHash);
  });
}
Formatted 1 file (1 changed) in 0.01 seconds.
