# Native permission test strategy

Audit 2026-10-11, base `4f10aab`. Refs #604. **DRAFT strategy only**: #594/BLU038 prerequisite unresolved, owner physical-device/TCC validation remains separate. Sole document; no permission grant/reset, native run, entitlement, workflow, source change, secrets or hardware takeover. Existing #15/#125/#39/#351 and retained-operation gates remain held.

## Answer and evidence tiers

Keep fake permission contracts in free tiny CI; require a separate owner-run, consent-scoped real Mac/device record before any native acceptance claim. A mock true is a fixture value, a compile success is build evidence and a live preflight is a point-in-time permission observation. None proves an input/capture operation succeeded or that future/revoked permission remains granted.

| Tier | Current source/fixture | What it proves and does not |
| --- | --- | --- |
| Dart unit/widget | [onboarding checks](../lib/services/onboarding_checks.dart), [watchdog](../lib/services/permission_watchdog.dart), [observation](../lib/services/permission_observation.dart), [recovery card](../lib/ui/permission_recovery_card.dart) and injected MethodChannels/stores | Ordering, baseline/delete/dismissal, failed/loading/current UI and prompt invocation contracts. No actual OS dialog/grant/revoke, signed identity or desktop access. |
| Hosted builds/static | current [CI](../.github/workflows/ci.yml) macOS/iOS, [CodeQL](../.github/workflows/codeql.yml) Swift traced xcodebuild | Compile/static evidence. RunnerTests has only an empty testExample; workflows do not execute a meaningful Swift permission suite. No real TCC verified. |
| Emulator/Xvfb | simulator install/launch/alive, Android APIs29/34 mocked control, Linux real Xvfb pointer/loopback lane | Selected launch/network/Linux input evidence, not macOS Accessibility/Screen Recording/Input Monitoring/Microphone. |
| Conditional self-hosted | native-validation repository-variable condition, self-hosted macos, integration_test | Observed #642 SKIPPED. Actual integration_test source injects native control MethodChannel even on Mac, so enabling this command alone would not test real bridge/TCC. No activation here; public untrusted PR/self-hosted risk needs owner security review independently of a permission grant. |
| Real owner lane | [VALIDATION.md](VALIDATION.md), named Mac/iPhone/Android as applicable | Only a completed scoped record can attest actual grant/deny/revoke/restart/capture/input behavior. No record generated in this draft. |

## Exact bridges and current gaps

[NativeControlChannel.swift](../macos/Runner/NativeControlChannel.swift) exposes local_bluey/control. isTrusted calls [ComputerControl](../macos/Runner/ComputerControl.swift)'s AXIsProcessTrusted; askPermission calls AXIsProcessTrustedWithOptions(prompt:true), separate from opening Accessibility settings. Screen preflight CGPreflightScreenCaptureAccess never requests; requestScreenCaptureAccess calls CGRequestScreenCaptureAccess. MicrophoneAccess reads AVCaptureDevice.authorizationStatus(.audio)==authorized. [NativeControl.dart](../lib/services/native_control.dart) maps nullable results to false; channel errors still propagate unless a caller catches them. Request return is not a permanent grant.

[ScreenReader](../macos/Runner/ScreenReader.swift) uses ScreenCaptureKit capture and Vision OCR, merges [ControlsReader](../macos/Runner/ControlsReader.swift) AX controls. Actual permission denial, missing capture image, AX errors/stale coordinates and lock/multiple-display behavior require real fixtures. ControlsReader guards trust for reads but AX attribute failures become missing values; valid empty controls must not automatically mean 'permission denied'. ComputerControl posts CGEvents and most effect methods return without a native receipt of the target operation. The declared notTrusted error is not a universal enforced gate on every native function. Do not equate nil result with observed click/type success; SafetyGate and tool execution remain independent admission layers.

[HoldKeyChannel](../macos/Runner/HoldKeyChannel.swift) preflights CGPreflightListenEventAccess, separately requests CGRequestListenEventAccess, refuses start without preflight, installs local/global NSEvent monitors and removes them at stop. start=true checks authorization/install path, not real event delivery across every app/session. [hold_key_bridge_test](../test/hold_key_bridge_test.dart) injects method results/events/clock; missing side/denial/disabling/malformed events are fake boundary evidence, not physical key monitoring.

LivePermissionChecker.localNetwork currently always returns false; it is 'not needed yet' by source convention, not an OS denial proof. RequiredGranted checks only microphone for the first-answer onboarding path; finishing onboarding is not all permissions ready. Read-only native microphone preflight is distinct from AudioRecorderDriver.hasPermission: [audio_capture_permission_test](../test/audio_capture_permission_test.dart) characterizes the locked record implementation request:true default, create ordering and errors without starting capture. A caller asking for permission may prompt, so do not promise every method named hasPermission is read-only.

Recovery card explicitly requests Screen Recording on Fix then NativeControl.openURL(settingsUrl). Current ComputerControl.openURL only accepts http/https, while settings URLs use x-apple.systempreferences; the card reports failure for unsupported/null/unrecognized results. [home_status_cards_test](../test/home_status_cards_test.dart) checks injected default-Fix failure and disposal, not actual OS pane behavior. Manual System Settings is the truthful recovery path, not a claimed successful deep link. Dedicated openAccessibilitySettings is a separate supported path. No bridge fix in this strategy.

Watchdog stores ever-granted baselines, per-id dismissal/epoch/order protects against late observations and registry clear; baseline removal is not OS revocation. PermissionObservation preserves retained list during failed/loading, coalesces fresh resume reads and fences disposed/dismissed results. Dismissing Later clears only the selected baseline at main's original caller, not a permission grant or whole-system reset. False/unknown/channel failure and actual OS denial must not be conflated.

Both [debug](../macos/Runner/DebugProfile.entitlements) and [release](../macos/Runner/Release.entitlements) app-sandbox=false; network client/server and allow-jit=true. These are not proof of containment or TCC grants. Current Mac minimum14.0 reduces legacy API availability concerns but does not validate a signed build on supported OS versions. Plist tests verify root-level usage strings/service types and native source/config anchors, not actual permission dialogs or privacy behavior.

## Proposed owner-run matrix, not execution authorization

Use a dedicated test account/device and fabricated blank window/audio/text. Record OS/device, exact app/Flutter/source SHA, signed bundle identifier/signing/distribution identity, existing grant state, language/display and intended permission. No credentials, third-party user files or private apps in captures. Owner decides whether to use fresh test account or adjust existing grants; do not reset all TCC or automate bypasses. Pin the build under test, since changing signer/path/build can change observed OS behavior.

| Scenario | Expected observable evidence | Failure/cleanup boundary |
| --- | --- | --- |
| Fresh deny/not-yet-asked | Launch/onboarding read preflights cause no unsolicited dialog; explicit selected Fix/hold triggers only intended request | Show unavailable/failed, no capture/input/recording before allowed action. 'Not needed yet' not real grant. |
| Explicit grant | OS dialog/settings state, fresh app observation, then separate controlled capture/input/mic test | Verify real pixels/safe typed text/audio indicator and bounded temp cleanup, not method-call success alone. |
| Revoke while active | Revoke selected permission via owner action, resume/fresh probe, feature failure visible | Stop capture/input/shortcut and prevent delayed outputs/actions according to current controller limits. Do not claim ongoing work was undone. |
| Restart/update identity | Quit/relaunch same signed build, then separately approved changed build/signature path | Record whether grants persist/re-prompt and fresh feature result; no automatic grant or assumed migration. |
| Lock/Stop/deny/error | Controlled lock, Stop during request/permission path, cancelled dialog, unavailable bridge | Observe no late capture/input/audio and no stuck permission UI; unresolved native timeout/cancellation stays a gap, not fake success. |
| Shortcut/Input Monitoring | Denied start installs none, allowed safe key sequence delivers events, stop/lock removes effects | Distinguish delivery versus authorization. Test held modifiers/Esc/other key; never record private keystrokes. |
| Screen/AX/multiple displays | Blank fixture window, fresh full/crop image and OCR/AX targets matched to actual pixels | No wrong target action from stale coordinates; false/empty AX read not universal denial classification. No raw retained screen export. |
| Local Network/phone | Explicit consent-scoped pairing/discovery on real devices, offline/reconnect/reinstall | Mock checker false and simulator launch insufficient; no credentials/pairing keys in report. |
| Delete/Later | Registry deletion/selected dismissal tested independently of OS permission state | Baseline/log/temp cleanup truth, reported partial failures, no claim OS grants revoked or remote data erased. |

Each cell records pass/fail/unverified plus exact build/state/observable result, not a single blanket 'TCC passed'. Retry only after a fresh state observation. Evidence contains narrow statuses/sanitized fixture screenshots with retention/audience agreed separately; no private screenshots or device logs collected by this plan. Rollback is a previously verified app build and disabled affected feature, not changing OS permissions without owner approval. Never substitute a settings-open result for a grant or automatically replay uncertain external actions.

## Fresh fake validation and remaining decisions

**168 unchanged tests passed, 0 new**: onboarding_checks, onboarding, permission_watchdog, permission_observation, permission_observation_notice, permission_baseline_deletion, permission_dismissal, privacy_plists, trust_observation, trust_settings_action, hold_key_bridge and audio_capture_permission and home_status_cards. Analyze clean; format 273 files/0 changed. These verify fake/channel/source/ordering/UI contracts, not real TCC, native timeout/termination or physical devices. No actual OS prompt/grant/reset/test was performed. This PR's exact-head required 5 and manager APPROVED remain pending gates.

Manager can select a later narrow inert contract/fixture; #594 and native rollout stay held. Owner alone can supply real device access, permission/signing/distribution decisions and approved sanitized capture scope. This document asks for none now, completes no generic #604 implementation checkbox and changes no shared acceptance map.

## Primary sources

Fetched 2026-10-11, reference facts only. API pages returned only title text; source behavior is additionally grounded in actual Swift calls and Apple's fetched support discussion, not an invented current OS guarantee.

- [Apple Screen Recording discussion](https://developer.apple.com/forums/thread/683860): CGRequest versus CGPreflight, historical availability bug and ScreenCaptureKit recommendation, not proof of current app operation.
- [CGPreflight API](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()) and [CGRequest API](https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess()): API identifiers; title-only fetch limitation.
- [AX prompt option](https://developer.apple.com/documentation/applicationservices/kaxtrustedcheckoptionprompt): API identifier; source prompt:true reviewed, title-only external fetch.
- [Apple sandbox entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html): entitlement scope separate from current TCC/capability evidence.
- [GitHub secure use](https://docs.github.com/en/actions/reference/security/secure-use): public/self-hosted/untrusted code and masking risks; no new native lane authorized.
