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
