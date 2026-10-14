# BLU-018 live AX observation slice (issue #571)

This additive, opt-in adapter uses the production HostControl snapshot and
resolveTarget seam. Call `withHostAxVerification` only after the existing
SafetyGate approval path and with a live explicit-consent callback. It retains
the delegate's approve/execute/verify sequence. A new snapshot precedes target
resolution; missing target, untrusted host, revoked consent, privacy-sensitive
screen text, native failure or kill-generation change all yield unknown evidence.
No screenshot, label or exception is stored, logged or sent to a service.

The host owns cancellation of in-flight native operations. This reader cannot
guarantee atomic AX snapshots across host changes; hardware/TCC validation,
artifact/tool readers and persisted cross-process verification remain gaps.
Rollback: stop constructing the opt-in wrapper.

Focused verification (requires a Flutter/Dart SDK):

```sh
flutter test test/host_ax_postcondition_reader_test.dart
flutter test test/postcondition_verifier_test.dart test/workflow_execution_test.dart
flutter analyze
```

No `dart format` operation was performed.
