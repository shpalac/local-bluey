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
