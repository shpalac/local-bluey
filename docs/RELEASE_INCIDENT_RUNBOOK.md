# BLU-079: Release and incident dry-run runbooks

Refs #637. This is a **local-only dry-run checklist**, not an execution or approval mechanism. The pure-Dart production service `ReleaseIncidentChecklist` in `lib/services/release_incident_checklist.dart` accepts an explicit scenario and the checks a human has independently confirmed. Missing checks are returned in stable order and fail closed. Even a fully confirmed list means *ready for human review*, not release authorization. No secrets, endpoints, logs, approval tokens, external calls or persisted artifacts are accepted by this API.

## Preflight and release

1. Identify incident/release owner, exact version, platform, source commit and immutable artifact digest. Have the owner explicitly acknowledge the selected scope.
2. Independently verify the artifact, its signer, environment and provenance. Do not use a passed unit test as evidence of a notarized or installed app. Refer to [release smoke plan](RELEASE_SMOKE_PLAN.md) and [release pipeline](RELEASE.md).
3. Review the previous known-good artifact, data/schema compatibility, and the exact reversible deployment change. Do not roll back by deleting local data or keys.
4. Confirm SafetyGate remains enabled and risky effects still need human approval; do not use `SafetyGate.setEnabled(false)` as a rollback switch. Review privacy boundary, local-only state and egress policy before any operator-driven change.
5. Record the yes/no checks without credentials or user data. If a check is missing, **block** and escalate. A green dry run is never permission to publish; a separate authorized owner and established release workflow decide.

## Bad migration / rollback

1. Stop a new rollout by the approved release control; do not assume that the tray Stop reverses completed native effects.
2. Preserve retained user data. Identify affected schema version, backing-store behavior and whether forward-written data is compatible with the selected previous version.
3. Review the rollback plan and SafetyGate requirements. If data compatibility or restoration is uncertain, **do not downgrade or destructively clean up**; escalate for reviewed migration recovery.
4. Validate recovery and startup against an isolated non-user fixture before an owner authorizes a separate deployment action. Record unresolved checks as missing, never passed.

## Privacy incident

1. Acknowledge an incident owner and use authorized containment controls; do not delete evidence, automatically upload raw screenshots, audio, tokens or diagnostic dumps.
2. Review potential data exposure against [privacy](DATA_PRIVACY_HELP.md) and [egress limitations](TROUBLESHOOTING.md). Missing egress history is not evidence of zero traffic.
3. Preserve only sanitized identifiers, time windows, status codes and evidence digests under the existing retention policy. Escalate scope/notification decisions to the responsible owner.
4. Confirm SafetyGate remains enforced; do not bypass approvals to collect more evidence or attempt remediation.

## Model outage

1. Establish the observed local or remote provider failure without sending private prompts to another endpoint.
2. Keep local-only restrictions and SafetyGate active. Report degraded/blocked behavior visibly; do not silently switch to a cloud provider.
3. Use existing [troubleshooting steps](TROUBLESHOOTING.md) to check configuration and model availability. Do not claim that the brain connectivity test proves voice/STT readiness.
4. Confirm recovery with fabricated inputs and explicit operator review before returning affected workflows to normal operation.

## Reproduce the dry-run evidence

```sh
flutter pub get --enforce-lockfile
flutter test test/release_incident_checklist_test.dart
flutter analyze
```

All tests are fake/offline; they make no release, rollback, permission, network or model action. Native distribution, incident response, TCC and real-device validation remain **manual gaps**, tracked separately. If any operation fails or is cancelled, preserve a sanitized error/status receipt and escalate. Never label unrun checks successful. See [rollout guidance](BLU-035-rollout-rollback.md) and [support](SUPPORT.md).
