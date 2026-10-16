# BLU-014: Versioned Workflow DSL

Version 1 is a declarative-only Dart schema implemented in `lib/workflows/workflow_dsl.dart`. It does not modify the existing Routine API or execute host actions.

- Accepted triggers: `manual`, `scheduled`, `event`.
- Accepted steps: `notify`, `wait`, `hostAction`.
- Validated fields: schema version, nonempty ID/target, nonempty steps, string lists, retry limit (0–3). Unknown top-level and step fields are rejected rather than silently dropped.
- Migrations: unsupported versions fail closed. A future version requires an explicitly reviewed migration, rather than silent interpretation.
- Concurrency and cancellation: no executor exists in this slice; parsing has no side effects.
- Consent and security: no egress, storage, secret logging, or automatic execution is performed.

## Acceptance coverage

`flutter test test/workflow_dsl_test.dart test/workflow_dsl_unknown_fields_test.dart` exercises round-trip serialization, malformed schema/steps/retry policy and declarative behavior. `dart analyze lib/workflows/workflow_dsl.dart test/workflow_dsl_test.dart` checks analysis.

Timeout, cancellation, permission denial, offline and restart cases are **not applicable to this parser-only slice**. Before a runtime executor is enabled, it must integrate with existing SafetyGate, enforce permission and explicit consent before every host action, and add deterministic fake-host tests for those cases.

## Rollback and CI lifecycle

Rollback is removal of this isolated module and tests; no persistence or migration is involved. The temporary acceptance workflow `.github/workflows/temp-issue-567.yml` must be removed and replaced by end-to-end feature CI when runtime integration is complete.
