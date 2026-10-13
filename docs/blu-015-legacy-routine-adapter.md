# BLU-015 — Legacy Routine compatibility adapter

Depends on BLU-014 (#567). This branch is stacked on
`feat/blu-014-versioned-workflow-dsl-567` because the DSL is not yet on main.

## Scope and ownership

- New pure adapter: `lib/workflows/legacy_routine_adapter.dart`.
- Existing `lib/services/routines.dart` and its legacy on-disk JSON,
  export/import, matching, and golden fixtures remain untouched.
- Supported subset: enabled legacy routines whose instructions begin
  `notify:` followed by a nonempty notification. They become a **manual**
  one-step `notify` Workflow with a `legacy-trigger:` precondition marker.
  This marker is compatibility metadata, **not an executable trigger**.
- Every other legacy instruction, disabled routine, automatic/scheduled trigger,
  retry, extra steps, privileges and postconditions is rejected instead of
  guessing how to execute it. Never interpret arbitrary instructions as actions.
- No registration, persistence, side effects, egress, logging of contents,
  or SafetyGate bypass. Callers must still explicitly approve any later
  execution through the existing safety layer.
- This is a conservative data converter, not a runtime bridge. User-visible
  migration remains disabled until a reviewed end-to-end integration exists.

## Acceptance and validation

Run `dart format --output=none --set-exit-if-changed lib/workflows/legacy_routine_adapter.dart test/legacy_routine_adapter_test.dart`,
`dart analyze lib/workflows/legacy_routine_adapter.dart test/legacy_routine_adapter_test.dart`,
`flutter test test/legacy_routine_adapter_test.dart test/workflow_dsl_test.dart test/routines_test.dart`,
and `flutter analyze`.

AC-1: existing Routine implementation and golden fixtures unchanged;
conversion is declarative and manual only. AC-2: positive, malformed,
unsupported permissions and safety failures covered. Timeout, cancellation,
offline, concurrent execution and restart are not applicable to pure synchronous
stateless conversion; existing RoutineStore tests own persistence/restart cases.
AC-3: no host invocation or secret/error echo. AC-4: CI pending.

Rollback: drop the adapter and its use sites; no migration or storage changes
to reverse. Follow-up: when BLU-014 is merged and the end-to-end routine/workflow
execution integration is available, delete the temporary CI and replace it with
permanent end-to-end CI that exercises import, preview, explicit approval,
SafetyGate, execution denial and restart.
