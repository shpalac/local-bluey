# BLU-004: opt-in encrypted ActivityStore and retention

Issue: [#557](https://github.com/shpalac/local-bluey/issues/557).
Implementation: `lib/services/encrypted_activity_store.dart` and
`lib/services/activity_store.dart`.

## Ownership and current scope

- `ActivityStore.memoryOnly` remains the only pre-verification in-memory
  foundation. No automatic observation pipeline or background capture is enabled.
- `EncryptedActivityStore.openDefault(retentionConsent: true)` is the narrow
  opt-in persistence entry point. It is **not** called by existing capture
  flows. The caller must obtain explicit runtime consent; the store separately
  demands a fresh capture-session consent and an `approved: true` result from
  upstream SafetyGate/privacy policy for each step.
- The database stores only immutable `ActivityStep` v1 records (IDs, UTC time,
  limited kind/classification, bounded confidence), never raw windows, OCR,
  screenshots, keyboard contents, credentials or freeform text.
- Production inventory: `DataRegistry` owns `activity_store`; its
  `clear` deletes that store and its encryption key only. The allowlisted
  `ActivityRetentionPolicy` forbids deleting routines, settings and any
  unknown/impersonated store.

## On-disk layout, key lifecycle and recovery

- Native SQLCipher is selected through `package:sqlite3` build hooks:
  `source: sqlcipher`. Startup checks `PRAGMA cipher_version` and both
  integrity checks. Ordinary SQLite is **never** an acceptable fallback.
- A random 32-byte raw key is written to OS secure storage **before** creating
  the encrypted database. The existing encrypted file is **never** replaced
  when its key is absent, invalid or wrong; the same holds for corruption.
  Errors contain no record content, key or absolute path.
- An unreadable, future-version or unknown legacy schema fails closed. A fresh
  schema-v0 file is migrated transactionally to the schema-v1 tables/index.
  There is no implicit downgrade or destructive rebuild.
- File: `<ApplicationSupport>/activity-v1.sqlite3`. Its `-journal`,
  `-wal` and `-shm` files belong to the same store. SQLCipher encrypts the
  underlying pages, `temp_store=MEMORY` avoids disk temp tables,
  `secure_delete=ON` clears deleted SQLite cells, and DELETE journal mode
  prevents indefinitely retained WAL data. Physical SSD wear-levelled blocks
  and external backups **cannot** be certified as erased.
- Closing a store revokes active session consent. Deletion fences all open
  connections at the same path before unlinking the DB and sidecars, then
  deletes the key. A failure is surfaced, not swallowed.
- No secrets, keys, protected storage values or activity records may appear
  in CI reports, logs, repository fixtures, or network requests.

## Retention contract

- **OFF by default**. Disk storage is unavailable until explicit retention
  opt-in. Runtime consent is separate from the mere existence of a key.
- After opt-in, activity metadata expires after **7 days** by default, with
  a strictly positive shorter duration configurable by the caller. Expired
  entries are purged on restart/open and on reads/writes, inside transactions.
  No indefinite activity retention is supported.
- The 7-day default follows the owner's later BLU-004 decision comment dated
  2026-10-11. It supersedes the earlier *proposed* 14-day metadata default in
  ADR-001. This distinction must be retained during ADR reconciliation.
- Session TTL is five minutes by default. Permission loss, app restart,
  cancellation or failure requires fresh explicit capture consent; the store
  itself cannot grant SafetyGate/privacy approval.
- The settings UI for selecting or confirming retention is BLU-005/#558 and
  is not claimed as delivered here.

## Automated acceptance

Temporary mapping: `docs/acceptance/temporary/issue-557.json`. The existing
`acceptance-evidence` job dispatches only the linked issue's exact named
test cases and fails on missing, skipped or failing cases.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test test/encrypted_activity_store_test.dart test/activity_store_test.dart test/activity_retention_policy_test.dart
python3 tool/issue_task_ci.py --mode unit
```

Synthetic on-disk tests assert a non-SQLite plaintext header, absence of a
known synthetic marker in ciphertext, wrong-key preservation and recovery,
corruption preservation, secure-storage outage, unknown schema refusal,
consent denial, restart TTL, duplicate/capacity bounds, no retained sidecars,
and deletion with a live DB connection.

Not applicable: offline network dependency (no networking), remote
permission prompts (key failures are tested; platform permissions require a
real Mac), asynchronous cancellation mid-statement (SQLite mutations are
synchronous and transactional; async vault calls fail closed). Negative
timeouts are represented by session timeout and bounded SQLite busy timeout.

## Independent release evidence needed before closing #557

1. On a signed macOS build, verify Keychain denial/revocation/restore and
   explicitly enabled retention; no plaintext DB, `-wal`, `-journal`, temp,
   application backup or crash-recovery artifact may contain sensitive bytes.
2. Kill the app during SQLite writes, restart, verify no partial records or
   plaintext artifacts, and check wrong-key/corrupted DB are not overwritten.
3. Use Settings > Data and privacy to delete the activity store and inspect
   the on-disk directory, key and absence of new capture until reconsent;
   verify unrelated routines and credentials survive *scoped* deletion.
4. Record test device/OS, exact commit, commands, sanitized outcomes and
   security reviewer approval in the PR.
5. Promote temporary AC mapping to permanent end-to-end integration tests
   before using a closing keyword, following
   `docs/acceptance/TASK_LIFECYCLE.md`.

## Rollback

Stop creating `EncryptedActivityStore` instances, leave capture disabled,
revert the registry integration only after a deliberate migration/restore
decision. Never downgrade to ordinary SQLite or auto-delete ciphertext on
failure. Explicit user-initiated deletion must target only the owned DB,
sidecars and key.
