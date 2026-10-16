# Teach Mode capture lifecycle (BLU-012, issue #565)

## Wiring and privacy boundary

`TeachCaptureSession` is an opt-in, memory-only component above
`ScreenWatch` and `CaptureMonitor`. It can start only after explicit
session consent and accepts at most ten minutes. A second concurrent start
is refused, including while privacy or permission checks are pending.
The public `indicator` exposes off/active/paused; UI integration must
render this visibly before shipping live user capture.

Each observation is gated twice by the session's local-only policy, app
allowlist and hard-deny/private-window/lock checks. Unknown and sensitive
contexts cause an immediate **paused** state if the session is still active.
Any previous uncommitted steps are cleared on pause. The user must call
`resume` explicitly before new observations can be captured. An operation
error similarly pauses rather than retaining or exposing its payload.
Local-only revocation, allowlist revocation and expiry stop capture and
clear pending steps. `cancel` and `dispose` synchronously clear memory
and fence pending asynchronous work. Restart defaults to off.

Only validated `action` and `target` identifiers are retained.
Draft previews are immutable and cannot auto-execute. No frames, typed text,
credentials, persisted state, network calls or host actions are added here.
This is not a substitute for SafetyGate approval on future workflow execution.

## Verification and open gates

Run `flutter analyze` and
`flutter test test/teach_mode/capture_session_test.dart test/teach_mode/capture_negative_paths_test.dart`.
Tests use a fake clock, injected local-only/allowlist checks and completers
for deterministic negative paths. No native permission or screen capture
is performed by these tests.

Issue #565 **remains open**. The always-visible product indicator and the
physical macOS TCC grant/revoke, lock and sensitive-window checks need
real-device validation. BLU-004 and BLU-006 integration also needs review.
See `docs/acceptance/temporary/issue-565.json` for the automated subset
and the unfulfilled manual acceptance criterion.

Rollback: stop using `TeachCaptureSession`. No schema or storage migration
is necessary because all capture session state is volatile.
