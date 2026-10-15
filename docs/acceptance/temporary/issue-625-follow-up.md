# Issue 625: permission center follow-up

The center delegates authorization to the existing SafetyGate; this change rechecks the same grant after the asynchronous gate result. A revoke, replacement, or expiry during a pending approval denies the old action. Gate failures are propagated rather than converted into approval.

Run: `flutter test test/permission_center_inflight_test.dart test/permission_center_test.dart`.

Native device privacy/TCC validation remains manual, as do platform-specific Routines and supported-OS compatibility checks. The pure Dart tests do not establish absence of secret/PII leaks across unrelated files or egress paths. No network calls or additional persistence are introduced by this change.

Rollback: revert only the permission-center recheck and added test/manifest evidence after review; do not remove pre-existing grant or SafetyGate behavior.
