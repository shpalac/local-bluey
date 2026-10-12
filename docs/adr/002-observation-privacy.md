# ADR-002 — Observation consent, screen frames, retention and threat model

**Status:** Proposed, 2026-10-11; not ratified by a recorded owner decision. **Issue:** [BLU-001 #554](https://github.com/shpalac/local-bluey/issues/554). **Decision authority:** none recorded here. Any delegated or owner approval must be cited from a verifiable source before this ADR is treated as accepted. **Scope:** proposed activity observation/Teach Mode; **not** a claim that the feature is shipped.

## Context and source audit

- `lib/services/privacy_guard.dart` enforces local-only endpoint policy and pattern-based screen-text redaction; these patterns are incomplete and do not establish safe window classification.
- `lib/services/frame_differ.dart` converts decoded image bytes to an in-memory 32x18 luma grid and releases owned image/codec resources; its difference output is **not** a privacy classifier. Reset invalidates pending work.
- `lib/services/safety_gate.dart` gates risky computer actions; observation consent cannot bypass it.
- `lib/services/data_registry.dart` and `lib/ui/data_privacy_section.dart` own existing data inventory/deletion UX; extend rather than create a competing delete mechanism.
- Historical #351 cannot currently be retrieved from GitHub (404); do **not** assume it authorizes persistent frame storage. Prior discussion is historical, not an active dependency.
- [ADR-001 / PR #651](https://github.com/shpalac/local-bluey/pull/651) records the previously selected defaults; this ADR provides explicit implementation contracts.

## Decisions

1. **Default off and no auto-resume.** Observation requires an explicit user action in each session and active OS permissions. A process restart, permission loss, user revocation, timeout or cancellation ends the session. No background collection or persistent opt-in to active capture.
2. **Fail closed before capture, model and disk.** Private/incognito windows, password/authentication surfaces, known sensitive content and unknown/unavailable classification are denied. A user granting observation permission does not override this policy. Classify from safe OS window metadata before requesting pixels when possible; if the metadata cannot be trusted, do not capture.
3. **Frame lifetime.** Frames may exist only in volatile memory for the minimal operation; never write raw frames to disk, logs, telemetry, crash artifacts, action history or an LLM endpoint as part of observation. On cancel/revoke, invalidate pending work and release resources. `FrameDiffer` is an optimization only, never evidence of safety.
4. **Retention.** No durable activity storage until BLU-004 verifies genuine at-rest encryption, protected keys, WAL/journal/backup behavior and deletion. Future retention is opt-in, finite (the TTL value is undecided: ADR-001 proposes 14 days for redacted opted-in metadata, and no number is fixed here) and visible in Settings; disabling must stop writers and purge retained activity and derived caches. Unrelated user-created Routines are not deleted by activity-only purge.
5. **Safety.** Observation cannot execute actions. Any later replay/automation passes the existing SafetyGate and explicit approval, including local-only endpoint checks. Failures must never silently downgrade security.
6. **Metadata.** Audit may record sanitized reason codes, timestamp and session identifier only; never window title, raw OCR, screenshot bytes, prompts, secrets or unbounded free text.

## Typed contract and ordering

`ObservationContext` supplies sessionActive, cancelled, userConsented, osPermissionGranted and `WindowSensitivity` (safe/sensitive/private/unknown). `ObservationPolicy.evaluate` returns a typed `ObservationDecision` with no I/O. **Allow** only if all checks are affirmative and sensitivity is explicitly safe. Callers must run the policy before any pixel acquisition and re-check on focus/permission changes and before processing each frame. Async cancellation invalidates in-flight frames; stale results must be discarded.

## Threat model

| Threat | Mitigation | Residual risk / test |
| --- | --- | --- |
| Password/private screen captured | Pre-capture metadata gate; unknown denied | Platform metadata can be incomplete; manual native validation required |
| Consent persists across restart | Session state only in memory; default-off | Restart/revocation tests |
| Screenshots/PII leak to disk or network | No frame persistence or observation egress; sanitize logs | Audit crash dumps/temp files and provider calls |
| Race after focus change or cancel | Generation invalidation, repeated gate check, resource cleanup | Async race and disposal tests |
| Encrypted storage claim without encryption | Keep memory-only until BLU-004 acceptance | Wrong-key, WAL, backup and corruption tests in BLU-004 |
| Unsafe auto-execution | Existing SafetyGate always applies | Fake-host negative tests |

## Rollout and verification

The pure policy and unit tests are introduced behind **no new user-visible feature**. Integrating capture/session lifecycle, native OS metadata classification, encrypted storage and retention UI are separate BLU-002–005/012 work. Validate with `dart format --set-exit-if-changed lib/services/observation_policy.dart test/observation_policy_test.dart`, `flutter analyze`, and `flutter test test/observation_policy_test.dart` on CI. Do not claim real-device permission validation until physically performed. Review must include privacy/security sign-off before any observation is enabled.
