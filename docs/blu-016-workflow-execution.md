# BLU-016 execution state machine

Depends on BLU-014 (#567 / PR #721). Declarative execution with optional durable interruption metadata; no automatic triggers or new network paths.

States: pending → running → approval → running → verifying → running (next step) → completed. Denied approval, verification failure, exception or deadline → failed. Cancellation → cancelled. Execution is single-flight.

The host adapter is an interface, not a production HostControl integration. Production adapters MUST enforce explicit consent, SafetyGate and privacy checks before performing actions. Cancellation and timeout are cooperative: a host operation already in progress cannot be forcibly interrupted; adapters must implement cancellation-aware side effects. Do not enable user-visible execution until that integration is verified.

Acceptance: deterministic fake-host tests cover order, concurrent run calls, denial, verification failure, cancellation, timeout and malformed DSL. Offline and restart recovery are not applicable to this memory-only slice; on restart a new execution must be explicitly started. No UI/golden changes.

Validation: `flutter pub get`; `dart format --output=none --set-exit-if-changed lib/workflows/workflow_execution.dart test/workflow_execution_test.dart`; `dart analyze lib/workflows/workflow_execution.dart test/workflow_execution_test.dart`; `flutter test test/workflow_execution_test.dart`.

Rollback: remove isolated executor and tests. Temporary CI must be removed and replaced with end-to-end SafetyGate/HostControl CI when the feature is integrated and enabled.


## Cancellation during recovery cleanup

After the last step verifies, the optional durable recovery marker is cleared
asynchronously. A cancellation or audited stop arriving while that cleanup is
pending must keep the result cancelled, never completed. The new fake-store
regression tests hold cleanup open deterministically and assert that no
`completed` audit event is written after cancellation.

This does not make host side effects reversible, nor validate physical device
permissions. The native iOS simulator TCC UX gap remains open in the
issue-specific acceptance manifest. No changes are made to the approval
prologue, request authorization timing or `WorkflowExecution._run()`.
