import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'activity_step.dart';

/// A storage error intentionally omits paths, keys, SQL statements and records.
final class EncryptedActivityException implements Exception {
  const EncryptedActivityException(this.reason);
  final String reason;

  @override
  String toString() => 'EncryptedActivityException: $reason';
}

/// Keep the key outside the encrypted database. Tests inject an in-memory vault.
abstract class ActivityKeyVault {
  Future<String?> read();
  Future<void> write(String hexKey);
  Future<void> delete();
}

/// Keychain on macOS/iOS, Keystore-backed secure storage on Android.
final class SecureActivityKeyVault implements ActivityKeyVault {
  const SecureActivityKeyVault();

  static const _keyName = 'activity_store.sqlcipher.key.v1';
  static const _secureStorage = FlutterSecureStorage();

  @override
  Future<String?> read() => _secureStorage.read(key: _keyName);

  @override
  Future<void> write(String hexKey) =>
      _secureStorage.write(key: _keyName, value: hexKey);

  @override
  Future<void> delete() => _secureStorage.delete(key: _keyName);
}

/// Opt-in, redacted ActivityStep persistence. Never accepts raw frames/text.
///
/// Opening a disk database requires explicit retention consent. A separate
/// short-lived session and per-step SafetyGate/privacy approval are needed to
/// write. It is deliberately not wired to automatic observation/capture.
final class EncryptedActivityStore {
  EncryptedActivityStore._(
    this._database,
    this._now,
    this.retention,
    this.capacity,
    this.sessionLength,
  );

  static const int schemaVersion = 1;
  static const String fileName = 'activity-v1.sqlite3';
  static const Duration defaultRetention = Duration(days: 7);

  final Database _database;
  final DateTime Function() _now;
  final Duration retention;
  final Duration sessionLength;
  final int capacity;
  DateTime? _sessionEndsAt;
  bool _closed = false;

  static String _randomKey() {
    final random = Random.secure();
    return List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static final RegExp _keyPattern = RegExp(r'^[0-9a-f]{64}$');

  /// Production path is in application support, not a user-selected location.
  static Future<EncryptedActivityStore> openDefault({
    required bool retentionConsent,
    DateTime Function()? now,
  }) async {
    final support = await getApplicationSupportDirectory();
    return open(
      file: File('${support.path}${Platform.pathSeparator}$fileName'),
      vault: const SecureActivityKeyVault(),
      retentionConsent: retentionConsent,
      now: now,
    );
  }

  /// Testable on-disk implementation. An existing DB with no key is NEVER
  /// rekeyed, deleted or replaced: its ciphertext is preserved for recovery.
  static Future<EncryptedActivityStore> open({
    required File file,
    required ActivityKeyVault vault,
    required bool retentionConsent,
    DateTime Function()? now,
    Duration retention = defaultRetention,
    Duration sessionLength = const Duration(minutes: 5),
    int capacity = 500,
  }) async {
    if (!retentionConsent) {
      throw const EncryptedActivityException('retention not authorized');
    }
    if (capacity < 1 ||
        retention <= Duration.zero ||
        sessionLength <= Duration.zero) {
      throw ArgumentError('invalid storage limits');
    }

    String? key;
    try {
      key = await vault.read();
      if (key == null) {
        if (await file.exists()) {
          throw const EncryptedActivityException('key unavailable');
        }
        key = _randomKey();
        // Protect the key *before* creating any persistent activity.
        await vault.write(key);
      }
    } on EncryptedActivityException {
      rethrow;
    } catch (_) {
      throw const EncryptedActivityException('secure key storage unavailable');
    }
    final rawKey = key;
    if (!_keyPattern.hasMatch(rawKey)) {
      throw const EncryptedActivityException('invalid protected key');
    }

    Database? database;
    try {
      await file.parent.create(recursive: true);
      database = sqlite3.open(file.path);
      // SQLCipher raw-key syntax: no password interpolation or KDF ambiguity.
      database.execute('PRAGMA key = "x\'$rawKey\'"');
      final cipher = database.select('PRAGMA cipher_version');
      if (cipher.isEmpty || cipher.first.values.first.toString().isEmpty) {
        throw const EncryptedActivityException('SQLCipher unavailable');
      }

      // A wrong key or damaged header must fail before *any* writes.
      database.select('SELECT count(*) FROM sqlite_master');
      final integrity = database.select('PRAGMA cipher_integrity_check');
      if (integrity.isNotEmpty) {
        throw const EncryptedActivityException('database integrity failed');
      }
      final normalIntegrity = database.select('PRAGMA integrity_check');
      if (normalIntegrity.single.values.first != 'ok') {
        throw const EncryptedActivityException('database integrity failed');
      }

      final version =
          database.select('PRAGMA user_version').single.values.first as int;
      if (version != 0 && version != schemaVersion) {
        throw const EncryptedActivityException('unsupported schema version');
      }
      if (version == 0) {
        // Version zero is valid only for an empty, freshly created database.
        if (database
            .select(
              "SELECT name FROM sqlite_master WHERE type='table' "
              "AND name NOT LIKE 'sqlite_%'",
            )
            .isNotEmpty) {
          throw const EncryptedActivityException('unknown legacy schema');
        }
      }

      database.execute('PRAGMA busy_timeout = 1000');
      database.execute('PRAGMA temp_store = MEMORY');
      database.execute('PRAGMA secure_delete = ON');
      // No plaintext temp DB; journal pages remain encrypted by SQLCipher.
      // DELETE mode also prevents an indefinitely retained WAL sidecar.
      final journal = database.select('PRAGMA journal_mode = DELETE');
      if (journal.single.values.first.toString().toLowerCase() != 'delete') {
        throw const EncryptedActivityException('unsafe journal mode');
      }
      if (version == 0) {
        database.execute('BEGIN IMMEDIATE');
        try {
          database.execute('''
            CREATE TABLE activity_steps (
              step_id TEXT PRIMARY KEY,
              timestamp_ms INTEGER NOT NULL,
              encoded_step TEXT NOT NULL
            )
          ''');
          database.execute(
            'CREATE INDEX idx_activity_time '
            'ON activity_steps(timestamp_ms)',
          );
          database.execute('PRAGMA user_version = 1');
          database.execute('COMMIT');
        } catch (_) {
          database.execute('ROLLBACK');
          rethrow;
        }
      }

      final result = EncryptedActivityStore._(
        database,
        now ?? DateTime.now,
        retention,
        capacity,
        sessionLength,
      );
      result.purgeExpired();
      return result;
    } on EncryptedActivityException {
      database?.close();
      rethrow;
    } catch (_) {
      database?.close();
      throw const EncryptedActivityException('encrypted database unavailable');
    }
  }

  void _requireOpen() {
    if (_closed) {
      throw const EncryptedActivityException('store closed');
    }
  }

  bool startSession({required bool consentConfirmed}) {
    _requireOpen();
    _expireSession();
    if (!consentConfirmed || _sessionEndsAt != null) return false;
    _sessionEndsAt = _now().toUtc().add(sessionLength);
    return true;
  }

  void _expireSession() {
    final ends = _sessionEndsAt;
    if (ends != null && !_now().toUtc().isBefore(ends)) {
      _sessionEndsAt = null;
    }
  }

  bool get isActive {
    _requireOpen();
    _expireSession();
    return _sessionEndsAt != null;
  }

  /// Transactionally remove expired entries, including after a restart.
  int purgeExpired() {
    _requireOpen();
    final boundary = _now().toUtc().subtract(retention).millisecondsSinceEpoch;
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute('DELETE FROM activity_steps WHERE timestamp_ms <= ?', [
        boundary,
      ]);
      final changed = _database.updatedRows;
      _database.execute('COMMIT');
      return changed;
    } catch (_) {
      _database.execute('ROLLBACK');
      throw const EncryptedActivityException('retention purge failed');
    }
  }

  bool add(ActivityStep step, {required bool approved}) {
    _requireOpen();
    _expireSession();
    if (!approved || _sessionEndsAt == null) return false;
    final now = _now().toUtc();
    if (step.timestamp.isAfter(now) ||
        !step.timestamp.isAfter(now.subtract(retention))) {
      return false;
    }

    _database.execute('BEGIN IMMEDIATE');
    try {
      final timestamp = step.timestamp.millisecondsSinceEpoch;
      _database.execute('DELETE FROM activity_steps WHERE timestamp_ms <= ?', [
        now.subtract(retention).millisecondsSinceEpoch,
      ]);
      if (_database.select('SELECT 1 FROM activity_steps WHERE step_id = ?', [
        step.stepId,
      ]).isNotEmpty) {
        _database.execute('ROLLBACK');
        return false;
      }
      _database.execute(
        'INSERT INTO activity_steps (step_id, timestamp_ms, encoded_step) '
        'VALUES (?, ?, ?)',
        [step.stepId, timestamp, step.encode()],
      );
      _database.execute(
        'DELETE FROM activity_steps WHERE step_id IN '
        '(SELECT step_id FROM activity_steps ORDER BY timestamp_ms DESC, '
        'step_id DESC LIMIT -1 OFFSET ?)',
        [capacity],
      );
      _database.execute('COMMIT');
      return true;
    } catch (_) {
      _database.execute('ROLLBACK');
      throw const EncryptedActivityException('activity write failed');
    }
  }

  List<ActivityStep> get snapshot {
    _requireOpen();
    _expireSession();
    if (_sessionEndsAt == null) return const [];
    purgeExpired();
    try {
      return List<ActivityStep>.unmodifiable(
        _database
            .select(
              'SELECT encoded_step FROM activity_steps '
              'ORDER BY timestamp_ms, step_id',
            )
            .map((row) => ActivityStep.decode(row['encoded_step'] as String)),
      );
    } catch (_) {
      throw const EncryptedActivityException('activity read failed');
    }
  }

  void stopSession() => _sessionEndsAt = null;

  /// Clears stored activity and revokes capture consent before doing any I/O.
  /// VACUUM is compacting, not a claim of secure physical SSD erasure.
  Future<void> clear() async {
    _requireOpen();
    stopSession();
    try {
      _database.execute('DELETE FROM activity_steps');
      _database.execute('VACUUM');
    } catch (_) {
      throw const EncryptedActivityException('activity clear failed');
    }
  }

  void close() {
    if (_closed) return;
    stopSession();
    _closed = true;
    _database.close();
  }

  /// Registry deletion does not create a new DB or require retention opt-in.
  static Future<void> deleteDefault() async {
    final support = await getApplicationSupportDirectory();
    await deleteFiles(
      file: File('${support.path}${Platform.pathSeparator}$fileName'),
      vault: const SecureActivityKeyVault(),
    );
  }

  /// Explicit deletion of this dedicated database and key. Never delete
  /// unrelated user data or claim physical/backup cryptographic erasure.
  static Future<void> deleteFiles({
    required File file,
    required ActivityKeyVault vault,
  }) async {
    try {
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final artifact = File('${file.path}$suffix');
        if (await artifact.exists()) await artifact.delete();
      }
      await vault.delete();
    } catch (_) {
      throw const EncryptedActivityException('activity deletion incomplete');
    }
  }
}
