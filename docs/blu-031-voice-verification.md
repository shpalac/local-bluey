# BLU-031 — Voice verification (secondary signal only)

The opt-in `VoiceVerifier` in `lib/services/voice_verification.dart` is a
**fake-testable contract**, not a released biometric authentication feature.
It accepts a local provider-supplied similarity and independent spoof verdict,
and returns a typed signal. It never authorizes a tool, stores a voiceprint,
starts recording, makes network requests, or changes `SafetyGate` policy.
`SafetyGate.authorize` still requires explicit human confirmation for risky
actions whenever that policy is enabled. A match, including score 1.0, cannot
approve actions on its own. Missing spoof evidence is `unavailable`.

Consent defaults off in every new process. The caller must actively opt in
with an enrollment ID; the verifier holds only that ID in process memory.
Cancel/revoke/restart increments a revision to discard late results.
A single deadline covers permission, readiness and assessment; permission,
offline, timeout, uncalibrated, invalid, and exception paths fail closed.
The injected assessor must be **on-device only**. Real microphone permission
and model readiness are intentionally delegated to a future reviewed adapter.

## Threat model and limitations

High similarity does not establish liveness; replay, synthesis and voice
conversion can deceive an embedding comparator. The default test threshold
is synthetic, **not calibrated for production**. No model, encryption-backed
enrollment store, privacy-safe action logging, recovery UI, or physical
mic permission integration is shipped here. Future changes must add
explicit consent UX with accessible English/Hebrew RTL presentation,
enrollment deletion, expiry, registry coverage, human-reviewed anti-spoof
attack trials, recorded FAR/FRR and on-device latency evidence before
enabling real speaker verification. No ambient audio reuse or cloud fallback.

## Tests and rollback

Run `flutter pub get`, `dart format --output=none --set-exit-if-changed
lib/services/voice_verification.dart test/voice_verification_test.dart`,
`flutter analyze`, `flutter test test/voice_verification_test.dart
test/safety_gate_test.dart`, and `flutter build apk --debug`.

No data migration is required. Revert the new module and its tests or
never call `VoiceVerifier.enable` to roll back; current behavior is
unchanged. Required CI and native tests must still pass before merge.
Issue #587 remains open for deployment and hardware evidence.
