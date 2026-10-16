import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/secure_storage.dart';

void main() {
  test('the shared store avoids the data-protection keychain', () {
    // Without this a locally signed macOS build fails every secure-storage
    // write with -34018 errSecMissingEntitlement.
    expect(
      secureStorage().mOptions.toMap()['useDataProtectionKeyChain'],
      'false',
    );
  });

  test('every secure-storage call site goes through the shared factory', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('lib/services/secure_storage.dart')) continue;
      if (file.readAsStringSync().contains('FlutterSecureStorage(')) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Construct secure storage through secureStorage() only.',
    );
  });
}
