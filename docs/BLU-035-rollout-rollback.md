# BLU-035 Rollout and rollback

## Scope

This document records the current repository behavior only. It does not claim rollout support for features that are not implemented on `main`.

## Current rollout guidance

- Keep changes behind explicit feature flags when introducing user-facing behavior.
- Preserve backwards compatibility with existing interfaces.
- Validate migrations before enabling persistent changes.
- Record operational changes in project documentation.

## Rollback guidance

For existing implemented behavior:

1. Disable the relevant feature flag when one exists.
2. Revert the deployment change if a safe flag rollback is unavailable.
3. Preserve user data and avoid destructive cleanup during rollback.
4. Validate application startup and regression tests after rollback.

## Out of scope

The following are documentation placeholders only because the related implementation is not present on current `main`:

- BLU-035-specific migration rollback automation.
- Feature-specific runtime rollback APIs.
- New SafetyGate, privacy registry, or ActionLog integrations.
- New user-facing rollout states.

These require their implementing issues before they can be documented as existing capabilities.

## SafetyGate is not a rollout feature flag

`SafetyGate.setEnabled(false)` pauses human confirmations for risky tools; it
is **not** a feature-specific rollback switch. Do not use it to roll back a
feature. Keep SafetyGate enabled while disabling the feature's own flag,
when such a flag exists. A disabled SafetyGate can permit risky tools without
a human approval prompt. The tray kill switch is separate: it blocks new
safety-gated actions, but does not undo effects already entered. Do not claim
that killing a session reverses a previously executed action.

Before declaring a rollback complete, inspect whether the changed feature has
a real flag and whether it introduced persistent data or network flows. If no
flag exists, follow the reviewed deployment revert procedure instead; do not
invent a preference key or delete retained user data. Check SafetyGate remains
enabled and verify subsequent risky actions still require approval.

## Default-off rollback smoke test

Use `flutter test test/blu_035_feature_defaults_test.dart` to verify that
newly created, consent-sensitive integrations default to disabled:
`FileIndex`, `VoiceVerifier`, `HomeAssistantAdapter` and
`PlaywrightBrowserAdapter`. The test uses rejecting fake providers and
constructs no network transport, native runner, stored credential or
background worker.

A green smoke test checks construction defaults, not a completed deployment
rollback. For each real feature, independently verify revoked consent,
running sessions, on-disk data, explicit tool approval and Mac/iOS/Android
behavior. Do not disable SafetyGate to simulate rollback.
