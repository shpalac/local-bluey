import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/activity_step.dart';
import 'package:local_bluey/services/encrypted_activity_store.dart';
import 'package:sqlite3/sqlite3.dart';

final class FakeActivityKeyVault implements ActivityKeyVault {
  String? key;
  bool unavailable = false;

  @override
  Future<String?> read() async {
    if (unavailable) throw StateError('no keychain');
    return key;
  }

  @override
  Future<void> write(String hexKey) async {
    if (unavailable) throw StateError('no keychain');
    key = hexKey;
  }

  @override
  Future<void> delete() async {
    if (unavailable) throw StateError('no keychain');
    key = null;
  }
}

void main() {
  late Directory dir;
  late File file;
  late FakeActivityKeyVault vault;
  var clock = DateTime.utc(2026, 10, 13, 10);

  ActivityStep step(String id, {DateTime? time}) => ActivityStep(
    stepId: id,
    sessionId: 'session_1',
    timestamp: time ?? clock,
    kind: ActivityKind.navigation,
    classification: ActivityClassification.internal,
    confidence: 0.75,
  );

  Future<EncryptedActivityStore> open({
    bool consent = true,
    Duration retention = const Duration(days: 7),
    int capacity = 3,
  }) => EncryptedActivityStore.open(
    file: file,
    vault: vault,
    retentionConsent: consent,
    retention: retention,
    capacity: capacity,
    now: () => clock,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('blu004_');
    file = File('${dir.path}/activity.sqlite3');
    vault = FakeActivityKeyVault();
    clock = DateTime.utc(2026, 10, 13, 10);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test(
    'real SQLCipher encrypts on-disk records and excludes raw text',
    () async {
      final store = await open();
      expect(vault.key, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(store.startSession(consentConfirmed: true), isTrue);
      expect(store.add(step('unique_secret_marker'), approved: true), isTrue);
      expect(store.snapshot.single.stepId, 'unique_secret_marker');
      store.close();

      final bytes = await file.readAsBytes();
      expect(bytes, isNotEmpty);
      expect(bytes.take(16).toList(), isNot('SQLite format 3\u0000'.codeUnits));
      expect(
        String.fromCharCodes(bytes).contains('unique_secret_marker'),
        isFalse,
      );
      final restarted = await open();
      expect(restarted.isActive, isFalse);
      expect(restarted.snapshot, isEmpty); // fresh consent after restart
      expect(restarted.startSession(consentConfirmed: true), isTrue);
      expect(restarted.snapshot.single.stepId, 'unique_secret_marker');
      restarted.close();
    },
  );

  test('wrong key fails closed and preserves original ciphertext', () async {
    final store = await open();
    expect(store.startSession(consentConfirmed: true), isTrue);
    expect(store.add(step('persisted'), approved: true), isTrue);
    store.close();
    final original = await file.readAsBytes();
    final trueKey = vault.key!;
    vault.key = 'f' * 64 == trueKey ? 'e' * 64 : 'f' * 64;
    await expectLater(open(), throwsA(isA<EncryptedActivityException>()));
    expect(await file.readAsBytes(), original);
    vault.key = trueKey;
    final recovered = await open();
    expect(recovered.startSession(consentConfirmed: true), isTrue);
    expect(recovered.snapshot.single.stepId, 'persisted');
    recovered.close();
  });

  test('damaged ciphertext fails without overwriting the file', () async {
    final store = await open();
    expect(store.startSession(consentConfirmed: true), isTrue);
    expect(store.add(step('persisted'), approved: true), isTrue);
    store.close();
    final original = await file.readAsBytes();
    original[0] ^= 0xff;
    await file.writeAsBytes(original, flush: true);
    await expectLater(open(), throwsA(isA<EncryptedActivityException>()));
    expect(await file.readAsBytes(), original);
  });

  test('key unavailable and no opt-in never create a database', () async {
    await expectLater(
      open(consent: false),
      throwsA(isA<EncryptedActivityException>()),
    );
    expect(await file.exists(), isFalse);
    expect(vault.key, isNull);
    vault.unavailable = true;
    await expectLater(open(), throwsA(isA<EncryptedActivityException>()));
    expect(await file.exists(), isFalse);
    vault.unavailable = false;
    final store = await open();
    store.close();
    vault.key = null;
    await expectLater(open(), throwsA(isA<EncryptedActivityException>()));
    expect(await file.exists(), isTrue);
  });

  test('TTL purge, capacity and denied writes survive restart', () async {
    final store = await open(retention: const Duration(hours: 1), capacity: 2);
    expect(store.add(step('denied'), approved: true), isFalse);
    expect(store.startSession(consentConfirmed: false), isFalse);
    expect(store.startSession(consentConfirmed: true), isTrue);
    expect(store.add(step('denied'), approved: false), isFalse);
    expect(
      store.add(
        step('future', time: clock.add(const Duration(minutes: 1))),
        approved: true,
      ),
      isFalse,
    );
    expect(store.add(step('a'), approved: true), isTrue);
    expect(store.add(step('a'), approved: true), isFalse);
    expect(store.add(step('b'), approved: true), isTrue);
    expect(store.add(step('c'), approved: true), isTrue);
    expect(store.snapshot.map((s) => s.stepId).toList(), ['b', 'c']);
    store.close();
    clock = clock.add(const Duration(hours: 2));
    final reopened = await open(retention: const Duration(hours: 1));
    expect(reopened.startSession(consentConfirmed: true), isTrue);
    expect(reopened.snapshot, isEmpty);
    reopened.close();
  });

  test(
    'clear revokes session, erases rows and leaves no WAL/journal',
    () async {
      final store = await open();
      expect(store.startSession(consentConfirmed: true), isTrue);
      expect(store.add(step('clear_me'), approved: true), isTrue);
      await store.clear();
      expect(store.isActive, isFalse);
      expect(store.add(step('no_second_capture'), approved: true), isFalse);
      expect(store.startSession(consentConfirmed: true), isTrue);
      expect(store.snapshot, isEmpty);
      store.close();
      for (final suffix in ['-wal', '-shm', '-journal']) {
        expect(await File('${file.path}$suffix').exists(), isFalse);
      }
      final restarted = await open();
      expect(restarted.startSession(consentConfirmed: true), isTrue);
      expect(restarted.snapshot, isEmpty);
      restarted.close();
    },
  );

  test(
    'schema rejects unknown versions without migrating or dropping data',
    () async {
      final store = await open();
      store.close();
      final db = sqlite3.open(file.path);
      try {
        db.execute('PRAGMA key = "x\'${vault.key}\'"');
        expect(db.select('PRAGMA cipher_version'), isNotEmpty);
        db.execute('PRAGMA user_version = 99');
      } finally {
        db.close();
      }
      final original = await file.readAsBytes();
      await expectLater(open(), throwsA(isA<EncryptedActivityException>()));
      expect(await file.readAsBytes(), original);
    },
  );

  test(
    'explicit deletion removes owned sidecars and revokes the key',
    () async {
      final store = await open();
      store.close();
      for (final suffix in ['-wal', '-shm', '-journal']) {
        await File('${file.path}$suffix').writeAsString('test sidecar');
      }
      await EncryptedActivityStore.deleteFiles(file: file, vault: vault);
      expect(await file.exists(), isFalse);
      expect(vault.key, isNull);
      for (final suffix in ['-wal', '-shm', '-journal']) {
        expect(await File('${file.path}$suffix').exists(), isFalse);
      }
    },
  );
}
