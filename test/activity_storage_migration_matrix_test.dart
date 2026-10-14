import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/activity_schema_preflight.dart';
import 'package:local_bluey/services/encrypted_activity_store.dart';
import 'package:sqlite3/sqlite3.dart';

final class MigrationKeyVault implements ActivityKeyVault {
  String? key;

  @override
  Future<String?> read() async => key;

  @override
  Future<void> write(String value) async => key = value;

  @override
  Future<void> delete() async => key = null;
}

void main() {
  late Directory directory;
  late File file;
  late MigrationKeyVault vault;

  Future<EncryptedActivityStore> open() => EncryptedActivityStore.open(
    file: file,
    vault: vault,
    retentionConsent: true,
  );

  void editEncryptedDatabase(void Function(Database db) edit) {
    final db = sqlite3.open(file.path);
    try {
      db.execute("PRAGMA key = \"x'${vault.key}'\"");
      expect(db.select('PRAGMA cipher_version'), isNotEmpty);
      edit(db);
    } finally {
      db.close();
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('blu055_');
    file = File('${directory.path}/activity.sqlite3');
    vault = MigrationKeyVault();
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('fresh install creates schema version one and reopens', () async {
    final first = await open();
    first.close();
    editEncryptedDatabase((db) {
      expect(db.select('PRAGMA user_version').single.values.first, 1);
      expect(
        db.select("SELECT name FROM sqlite_master WHERE name='activity_steps'"),
        hasLength(1),
      );
    });
    final second = await open();
    second.close();
  });

  test(
    'future schema downgrade refuses without rewriting ciphertext',
    () async {
      final first = await open();
      first.close();
      editEncryptedDatabase((db) {
        db.execute('PRAGMA user_version = 2');
      });
      final original = await file.readAsBytes();
      await expectLater(
        open(),
        throwsA(
          isA<EncryptedActivityException>().having(
            (error) => error.reason,
            'reason',
            'unsupported schema version',
          ),
        ),
      );
      expect(await file.readAsBytes(), original);
    },
  );

  test('unknown legacy schema refuses instead of migrating', () async {
    final first = await open();
    first.close();
    editEncryptedDatabase((db) {
      db.execute('PRAGMA user_version = 0');
    });
    final original = await file.readAsBytes();
    await expectLater(open(), throwsA(isA<EncryptedActivityException>()));
    expect(await file.readAsBytes(), original);
  });

  test('schema preflight rejects future versions without SQL writes', () {
    final db = sqlite3.openInMemory();
    try {
      db.execute('PRAGMA user_version = 3');
      expect(
        () => ActivitySchemaPreflight.verify(db, supportedVersion: 1),
        throwsStateError,
      );
      expect(db.select('PRAGMA user_version').single.values.first, 3);
    } finally {
      db.close();
    }
  });
}
