# BLU-018 — Postcondition verification

## Contract

`Postcondition.parse('ax:button=Done')`, `file:receipt=present` and
`tool:status=ok` define **expected observations**, never commands. The
host-owned `PostconditionReader` resolves observations locally only, after
host permission checks. The engine neither reads files nor issues requests.
A null observation, thrown error or timeout returns `inconclusive`; differing
evidence returns `rejected`; matching evidence returns `confirmed`.

`VerifyingWorkflowHost` is an opt-in adapter. It retains the existing
`WorkflowHost.approve`, `execute` and `verify` checks, requiring independent
postcondition confirmation before `WorkflowExecution` advances. It does
not enable capture or add persistent state. An empty condition list fails
closed. Cancellation is cooperative; external host calls must be separately
cancelled by their owner.

## Rollback / failure handling

Remove the opt-in adapter to revert to existing host behavior. A denial,
unavailable observation, unexpected exception, cancelled evaluation or timeout
never confirms success. The engine stores no observed values in logs or disk.
No automated retry or action replay is performed.

## Scope limitations

This is a pure-Dart, fake-host-tested feature slice; production AX/HostControl,
SafetyGate and artifact readers are not wired. In particular, 'file' observes
only an injected provider response, not an arbitrary filesystem path.
No persistent restart recovery is implemented. Hardware/TCC permission
acceptance and real Mac integration need manual/e2e validation.
Do not replace temporary CI with end-to-end CI until those integrations land.

## Reproduce

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib/workflows/postcondition_verifier.dart test/postcondition_verifier_test.dart
dart analyze lib/workflows/postcondition_verifier.dart test/postcondition_verifier_test.dart
flutter test test/postcondition_verifier_test.dart test/workflow_execution_test.dart
flutter build bundle --release
```

## Timeout and cancellation read fencing (Refs #571)

A timeout now invalidates the remaining verification sequence. An already
started asynchronous read may still complete, but no following condition is
requested after its late result. Explicit cancellation has the same ordering
guarantee. This avoids further potentially sensitive observations after the
caller has abandoned verification and never upgrades an expired attempt to
confirmed success.

Run `flutter test test/postcondition_timeout_fence_test.dart` for the
deterministic outstanding-read regression. The native permission and
artifact/tool observation gaps remain and this work does not complete #571.
