# BLU-020 — execution audit and stop

Scope: optional local-only audit integration for `WorkflowExecution`. No
telemetry, database writes, file writes, clipboard actions or background
capture. Production callers must explicitly construct and pass
`ExecutionAudit` and render `ExecutionAuditPanel` to enable the UI.

## Ownership and contracts

- `lib/workflows/workflow_execution.dart`: existing single-flight runner owns
  cancellation, timeout, approval, step ordering and cooperative host semantics.
- `lib/services/execution_audit.dart`: bounded memory-only records with
  allowlisted event labels, numeric step indices and always-redacted diagnostics.
  The raw step target, host errors, workflow ID and payload never enter audit.
- `lib/ui/execution_audit_panel.dart`: optional timeline, stop button and
  explicit two-stage dialog for local display of redacted JSON.
- `WorkflowHost` implementations still own SafetyGate and native permissions.
  This change cannot interrupt an in-flight native side effect; stop prevents
  later steps once the current host future settles.

## Fail closed

Invalid DSL is rejected by `WorkflowDefinition` before execution.
Denied permission stops before dispatch. Timeout stops subsequent steps;
in-flight host effects must be cancellation-aware and must not be assumed undone.
Audit records are ephemeral on restart and cannot resume effects. Persistent
checkpoints are covered by BLU-019; unverified dispatched effects need manual
reconciliation rather than replay. Offline host errors fail the workflow; exception
messages are never included in audit. Diagnostics require explicit consent and
are shown locally, not transmitted or automatically copied.

## Evidence

Temporary PR CI: `flutter pub get`, `dart format` (focused files),
`flutter analyze`, `flutter test test/execution_audit_test.dart
test/workflow_execution_test.dart`, `flutter build web --release`.

Tests cover multi-step success, stop during a pending host action, denied
permission, redacted fields, bounded event memory, export consent, widget
stop/export cancellation, malformed DSL and timeout (existing runner tests).

## Remaining end-to-end integration

The production HostControl/SafetyGate adapter must explicitly wire the opt-in
panel into its execution lifecycle. Mac TCC/hardware validation and
restart/recovery integration are not validated by this pure-Dart feature slice.
Keep #573 open until those are verified. Once the integration is enabled and
covered, replace the temporary CI with a permanent end-to-end acceptance job.

Rollback: omit the optional audit argument and panel, or revert this isolated PR.
