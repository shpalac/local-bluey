# BLU-017 — Workflow action preview and approval (isolated slice)

Depends on BLU-014 (#567), BLU-015 (#568), and BLU-016 (#569), now on main.

`WorkflowApprovalHost` is an opt-in `WorkflowHost` adapter. Existing
executors and hosts are unchanged. The preview exposes action type, target,
declared workflow permissions and whether the action is a host action.
A prompt grants only the exact step index in the validated workflow.
Every step requires explicit consent; the injected policy must consult the
existing SafetyGate immediately before execution, including on non-host steps.
Deny, unavailable UI, revoked grants and safety denial fail closed.
Grants are memory-only and do not survive restart.

The adapter does not write to disk, contact the network, enable triggers or
automatically approve anything. Targets can be sensitive; callers must avoid
logging, persisting or sending previews to remote services. Host adapters must
redact sensitive values in their presentation as appropriate.

**Limitations:** No production SafetyGate/HostControl/UI wiring is enabled.
The delegate must independently enforce its existing native SafetyGate.
Revocation during an already-started delegate call is cooperative; the
delegate must implement cancellable native actions. No golden/RTL changes,
because this slice has no UI. Offline is simulated by a failing prompt;
restart resets grants. No macOS TCC/hardware evidence is claimed.

Validation:
```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib/workflows/workflow_action_approval.dart test/workflow_action_approval_test.dart
dart analyze lib/workflows/workflow_action_approval.dart test/workflow_action_approval_test.dart
flutter test test/workflow_action_approval_test.dart test/workflow_execution_test.dart
flutter build web --release
```

Rollback: remove the opt-in adapter, its tests and temporary CI. Keep the
temporary CI until native SafetyGate/HostControl end-to-end tests replace it.
