# BLU-013 draft builder (initial isolated module)

The pure Dart builder converts a restricted list of sanitized action metadata
into typed in-memory steps. Unknown actions, invalid targets and unexpected fields
are marked uncertain. No raw input values are retained, and drafts cannot execute.

The existing `TeachCaptureSession.review()` uses this builder to produce
in-memory snapshots from consent-gated sanitized observations. The draft remains
non-executable; it is not wired into a visible approval UI or the versioned
Workflow DSL (BLU-014). It does not persist drafts or invoke SafetyGate or
HostControl. The future execution boundary must require explicit approval.

Reviews inspect at most `TeachDraftBuilder.maxReviewSteps` (256) sanitized
observations. Larger input emits an explicit warning that additional steps were
omitted; consumers must not interpret such a partial preview as a complete
demonstration. This caps preview conversion time and output size, but the
upstream capture session still needs its own input-collection bound.

## Validation

`dart format --output=none --set-exit-if-changed lib/teach_mode/draft_builder.dart test/teach_mode/draft_builder_test.dart`
`dart analyze lib/teach_mode/draft_builder.dart test/teach_mode/draft_builder_test.dart`
`flutter test test/teach_mode/draft_builder_test.dart test/teach_mode/draft_preview_test.dart test/teach_mode/draft_bounded_preview_test.dart`

Timeout, cancellation, offline, permissions and restart are not applicable to
this synchronous, memory-only transformation. End-to-end integration is pending
the upstream capture and DSL contracts. The temporary workflow must be removed
and replaced with permanent end-to-end feature CI when those integrations land.
Rollback: remove this isolated module and its test; no persisted state exists.
