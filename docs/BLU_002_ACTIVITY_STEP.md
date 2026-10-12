# BLU-002 — ActivityStep v1 contract

**Status:** proposed implementation, review required. **Owner decision:** [#555](https://github.com/shpalac/local-bluey/issues/555). **Prerequisite:** BLU-001 privacy policy ([PR #665](https://github.com/shpalac/local-bluey/pull/665)); not yet assumed merged.

## Implementation

`lib/services/activity_step.dart` defines immutable `ActivityStep` with strict version 1 serialization, canonical UTC millisecond timestamp (`YYYY-MM-DDTHH:MM:SS.mmmZ` only; offsets, other precisions and sub-millisecond values are rejected), an encoded-size bound (512 characters) checked before JSON parsing, opaque identifiers, bounded finite confidence, closed enums, and a small fixed field set. Unknown fields, versions, enum values and malformed payloads throw `ActivityStepFormatException`. There is no permissive migration from unknown schemas: explicit migration functions must be reviewed and tested for any known older schema before adding one.

The DTO intentionally contains **no raw screenshots, OCR, prompts, file paths, window titles, keystrokes, credentials, free-text metadata or model output**. It is not a screen capture or storage API. No activity persistence is enabled; BLU-004 encryption remains a prerequisite to any disk retention. The existing `PrivacyGuard`, `SafetyGate`, `FrameDiffer` and `data_registry` continue to own their current behavior. No action execution or network egress is added.

## Tests and integration gates

Run `flutter test test/activity_step_test.dart`, `flutter analyze` and `dart format --set-exit-if-changed lib/services/activity_step.dart test/activity_step_test.dart`. Tests cover canonical round-trip, invalid JSON, enum rejection, unknown schema, extra fields, non-finite/out-of-range confidence, canonical-only timestamps, sub-millisecond rejection, oversized and deeply nested input, and invalid IDs. No UI goldens needed (no UI change). Offline, permission, timeout, restart and cancellation are not DTO operations; test these in the future capture/session lifecycle integration, never infer them from pure serialization tests.

**Rollout:** unused DTO, no feature flag needed until integrated. **Rollback:** revert this isolated module and tests. **Security review:** validate the approved allowlist and memory-only behavior before integrating with any producer.
