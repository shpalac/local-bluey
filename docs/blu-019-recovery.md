# BLU-019 — Recovery safety

The opt-in recovery contract is isolated and not wired to production actions.
A durable `RecoveryStore` must atomically commit a dispatched checkpoint
**before** an external side effect. After restart, any unverified dispatch
fails closed and requires explicit reconciliation; it is never resent.

This provides at-most-once attempts, not guaranteed exactly-once delivery.
Production integration requires BLU-018 postcondition verification and an
encrypted durable store (BLU-004). Do not store message bodies, credentials,
or raw secrets in checkpoints. Store implementation must serialize concurrent
writers or use compare-and-swap.

Validation: `flutter test test/workflow_recovery_test.dart`,
`flutter analyze`, `flutter build web --release`.
Rollback: disable recovery integration; do not discard uncertain checkpoints.

## Durable retry checkpoint write hardening (Refs #572)

`DurableRetryCheckpointStore.claim` flushes the started marker before
returning. A half-created claim file is treated as corrupt on recovery and
never removed or reused automatically. Completion writes reserve an exclusive
same-directory staging file, flush the serialized phase and rename it into
place. A concurrent writer or stale `.tmp` refuses the write rather than
overwriting uncommitted staging data. Partial stages require manual
reconciliation; they are not silently mistaken for verified delivery.

The test file `test/durable_retry_atomic_write_test.dart` covers
half-created claims, conflicting staging files and completed cleanup.
This improves local crash behavior but does not prove whole-system durability
under power loss or atomicity across machines. The production executor
integration and macOS restart harness remain incomplete.
