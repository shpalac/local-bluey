# BLU-013 draft builder (initial isolated module)

The pure Dart builder converts a restricted list of sanitized action metadata
into typed in-memory steps. Unknown actions, invalid targets and unexpected fields
are marked uncertain. No raw input values are retained, and drafts cannot execute.

This module is not yet wired into Teach Mode capture (BLU-012) or the versioned
workflow DSL (BLU-014). It does not persist drafts or invoke SafetyGate or HostControl.
The integration boundary must require explicit approval before any execution.

## Validation

`dart format --output=none --set-exit-if-changed lib/teach_mode/draft_builder.dart test/teach_mode/draft_builder_test.dart`
`dart analyze lib/teach_mode/draft_builder.dart test/teach_mode/draft_builder_test.dart`
`flutter test test/teach_mode/draft_builder_test.dart`

Timeout, cancellation, offline, permissions and restart are not applicable to
this synchronous, memory-only transformation. End-to-end integration is pending
the upstream capture and DSL contracts. The temporary workflow must be removed
and replaced with permanent end-to-end feature CI when those integrations land.
Rollback: remove this isolated module and its test; no persisted state exists.
