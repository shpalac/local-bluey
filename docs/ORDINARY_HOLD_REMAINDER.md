# Ordinary hold-to-talk remainder

Source snapshot: main `8074a2d758be4f73f0153608446464f2fd4857b4`, 11 October 2026. [#447](https://github.com/shpalac/local-bluey/issues/447) is a read-only audit, not activation, issue disposition or a broader gesture/key winner policy. Only this document changes.

## Answer

The capture owner already joins entered start/cap/stop/close and accounts for one transferred file. The delivered key owner also fences permission against release/cancel and uses acquisition identity. Ordinary Mac space/face and phone holds still call legacy permission/start/stop without their own intent identity or end-before-permission fence. Those outer caller paths, their safe error/lifetime display, and ordinary shared-capture ownership need a selected follow-up. A generic wrapper or automatic retry is not safe: Mac key, space and face share one capture, and generic stop may consume the current key token's output. No native failure was reproduced.

## Criteria and current delivery

[README](../README.md) says press/hold, release answers; its voice-recordings line promises deletion after use, stale sweep and a two-minute cap. [User guide](USER_GUIDE.md#the-voice-flow-step-by-step) describes Listening, release, transcription and answer, with failure feedback. These are user-flow anchors, not proof that every raw callback handles every failing await.

[Original #246](https://github.com/shpalac/local-bluey/issues/246) remains shpalac-owned/open. [Merged PR254](https://github.com/shpalac/local-bluey/pull/254), head `ab7468914b609bd9694f1d5d4a1966ed9c5c7f57`, merge `23eb2cb7f12ee4c83b3197ab44375b49fa56f817`, delivered tracked cap/release joining. Current source also contains later uncertainty/token work. Do not restate its old untracked-cap race as current or close it from this audit.

[Acceptance map](ACCEPTANCE_MAP.md#391-key-only-recording-intent) records key intent, partial-start containment and later identity stages: #415/PR416 acquisition/cleanup; #417/PR418 release; #419/PR420 actual key adoption; #421/PR422 independent cleanup action. Current actual source/fixtures confirm the bounded mechanisms below. That map's historical test totals/review ledger are preserved evidence, not a fresh all-PR CI review here. [#393 native condition](ACCEPTANCE_MAP.md#393-partial-start-and-failed-stop-capture-contract) stays separate. [#228](https://github.com/shpalac/local-bluey/issues/228) explicitly excludes changing face gesture; its global-key/platform criteria and shpalac ownership are not transferred.

## Source paths

### Mac space and face

[MacHome](../lib/main.dart) owns `_capture`, shared by `KeyRecordingIntent`. Normal branch `KeyboardListener` space-down changes face/bubble, calls `hasPermission().then`, and calls `start()` only on true without returning/observing its completion. Space-up calls `_onHoldEnd` without awaiting its returned future. FaceScreen start changes display, awaits permission then start, or shows denied text. Its end points to `_onHoldEnd`. Neither ordinary start stores a gesture generation, acquisition handle or ended flag. No killed/mounted check surrounds their permission continuation. Key's checks must not be attributed to these paths.

`_onHoldEnd` awaits generic `_capture.stop()`. For null it awaits permission again and directly sets bubble/face without a post-await mounted guard. For file it enters `_processUtterance` and the current runner. The null-path permission failure, stop rejection, start rejection and late denied/null UI do not have ordinary caller containment. The runner's guarded hooks cannot repair a failure before it is entered.

Mac dispose starts key/capture close through `_disposeKeyCapture`, which waits `closeCapture`, attempts capture disposal even if key cleanup fails and consumes its failure status. This is delivered shared closing, not proof that ordinary permission callbacks will never resume. A late ordinary start after capture disposal is rejected by `_disposed`, not allowed to record; its ignored future may reject. Capture disposal is entered after ordered key close, so
caller-lifetime end and capture `_disposed` are separate moments. No claim of post-dispose new driver entry follows from the missing caller fence.

### Phone client

[IosHome](../lib/main.dart) has a separate capture, used for iOS/Android phone role, not the Mac key capture. Start sets Listening, sends `holdStart`, fires haptic, then awaits permission/start. Denied permission fires error haptic but does not supply a new denied bubble there. End clears bubble, sends `holdEnd` first, awaits generic stop, reads file bytes, sends `holdAudio`, and attempts quiet deletion in `finally` around read/send. Stop failures before that block do not reach its file cleanup; a returned file is deleted best-effort even if read/send throws. No delivery receipt or physical-erasure guarantee follows.

`MacLink.send` is a nullable local connection send, not an acknowledgment. Phone end timing is retained: `holdEnd` precedes capture stop and `holdAudio`. No replacement timing/policy is selected. IosHome dispose stops link, calls capture.dispose without observing completion, and closes reply owner separately. Capture's disposed guard/entered close still apply; outer permission/file-read continuations have no phone-generation fence. A late send attempt can hit the stopped/null link, and is not proof of remote delivery. Reply cleanup does not own input capture.

### Face dispatch and permission boundary

[FaceScreen](../lib/ui/face_screen.dart) uses VoidCallback start/end for both long-press and custom semantics Start listening/Stop and send. It does not await, coalesce or contain callback futures and has no long-press-cancel callback here. This is dispatch source, not a reproduced lost-cancel event. Existing [a11y widget tests](../test/face_a11y_test.dart) verify the real semantic actions dispatch and status live region, not mounted MacHome/phone permission/start ordering.

[AudioCapture](../lib/services/audio_capture.dart) and RecorderDriver comments call permission read-only/never prompting. Actual AudioRecorderDriver delegates `_r.hasPermission()` with no argument. Locked [dependency record](../pubspec.lock) is record7.1.1, record_platform_interface2.1.0, record_macos2.1.1, record_ios2.1.1, record_android2.2.0; path_provider2.1.6. In the inspected installed record7.1.1 `lib/src/record.dart`, `AudioRecorder.hasPermission({bool request = true})` forwards request. Its `_safeCall` waits creation and serializes platform calls via semaphore. Installed record_macos2.1.1 `RecordMacOsPlugin.handleHasPermission` requests AVCaptureDevice audio access for notDetermined when request=true, returns existing authorized/denied otherwise. Thus the production call is potentially requesting, contrary to local comments. No prompt was run. Android/iOS permission UX or revocation timing is not inferred from the Mac source. This audit changes neither consent behavior nor the driver argument.

## Exact remaining interleavings

1. **Permission pending, release before start entry.** Ordinary caller has not installed capture `_startOp`; `stop()` can return null. Later true permission has no ordinary ended-generation check and may call legacy start while capture remains open for use. Record's per-platform semaphore serializes individual calls, not this gesture intent. Required proof: invoke actual home callback with held permission, end before resolving, assert eventual driver calls and latest UI/file delivery. Existing owner-start fixtures do not model this outer permission gap. This is source-derived possibility, not a native reproduction.
2. **Entered start then release/cap/dispose.** Already protected: start is joined by stop/close; cap and release share `_stopOp`; one file claimant, pending/uncertain prior session blocks next start. `_disposed` blocks a new start and entered disposal waits cleanup. Do not claim every release permits late recording. Partial entered start/failed stop retains typed uncertainty and blocks fresh acquisition, with explicit owner cleanup behavior. Native stop/dispose success is not proved by fake driver completion.
3. **Permission/null-display after lifetime end.** Ordinary denied/null branches can call setState after awaits without mounted check; late start after disposed capture rejects. Phone file-read/send after close lacks current-gesture/lifetime publication gate. Required proof separates already-entered file effects from later display/send and checks uncaught failures. No automatic restart/retry is authorized.
4. **Repeated semantics/start/end.** Capture start idempotence and same-stop exact-once file claiming are delivered. But successive permission completions have no ordinary gesture identity and repeated null end can issue another potentially requesting permission probe/display. 'Only one native start while active' does not establish the intended gesture owns the result. Repeated read failures/delete failure are distinct from duplicate driver entry.
5. **Shared Mac key/space/face.** Key `acquire()` refuses busy legacy capture; key cannot claim it. But ordinary legacy start can return as an idempotent no-op while key capture is active without owning it, and ordinary generic stop can consume its file and set token outcome transferred. Stale key release/cleanup cannot touch a newer capture and cannot delete external transferred output. Delivered per-token safety is not symmetric ordinary ownership or a winner rule. An ordinary generic stop when its own permission has not started may consume a key session. No wrapper/retry should activate until the exact ownership seam and interaction policy are selected.

## Delivered capture, request and phone protections

- Capture installs candidate before driver.start, retains partial/failed-stop uncertainty, joins cap/release/close, and guards prior pending/cleanup state. Successful-current-null can mean confirmed injected stop with cleanup receipt; a generic wrapper null is not gesture ownership proof. Stale sweep/quiet deletion suppress errors, so neither guarantees physical erasure. Same millisecond legacy path naming/stale sweep should be included in any proposed capture/file matrix, not changed here.
- [Key intent](../lib/services/key_recording_intent.dart) checks current generation/ended/allowed after permission, retains token before started await, token releases send and token cleans cancel. Captured File ownership is separate after transfer. Dedicated explicit recovery and [cleanup caller](../lib/services/key_cleanup_caller.dart) are delivered, not ordinary gesture retry authority.
- [RequestRunner](../lib/services/request_runner.dart) now serializes one run, bounded queue default2, rejects excess with cleanup and discards revoked queued generations after Stop. [#366](https://github.com/shpalac/local-bluey/issues/366) old overlap evidence is not current source. It does not prevent two input gestures from consuming a shared recording before process admission.
- [PhoneAudioReceiver/intake](../lib/services/phone_audio.dart) handles payload staging/refusal, 8MiB bounds and superficial ftyp container check, unique same-clock filenames, entered partial-write cleanup, inactive suppression and runner errors. Quiet deletion remains best-effort. Callback failures are intentionally forwarded to the zone by tracked handler, not universally swallowed. Ordinary phone hold input is upstream and separate.
- [Phone reply owner](../lib/services/phone_reply.dart) and [#372](https://github.com/shpalac/local-bluey/issues/372) concern say playback/output, not ordinary mic input. Preserve that delivered owner and current receipts/haptics/link protocol.

## Smallest future candidates, not selected work

**Preparation only:** actual ordinary caller seam/matrix separating Mac space, face and phone, with explicit permission intent end/lifetime fencing and safe generic error display. Preserve legacy behavior until owner review. A source/fixture-only preparation can identify conflicting shared ownership without choosing a winner.

**Ownership-dependent:** ordinary use of actual acquisition token for start/release/cleanup, accounting for busy key/space/face, externally transferred file, cap and disposal. This is a candidate only. Decide whether overlapping gestures join, reject, replace or stay independent before activation; none is implied by key exclusivity. Coordinate shpalac #246/#228 and unpublished work, not silently take capture/core ownership.

**Phone-local candidate:** contain awaited permission/start/stop/read failures and suppress stale display/send while retaining current holdStart/holdEnd/holdAudio order and best-effort cleanup. Do not choose remote timing, new receipt, reconnect resend or automatic retry. Phone/request/reply ownership #366/#372 remains separate.

Native partial-open/stop semantics #393, held #351/#266/#344, Settings/onboarding/tutorial and permissions policy remain outside. No hardware, paid/recurring tests, secrets, permission changes or #160 work.

## Proposed actual-caller matrix

Not implemented in this docs-only task. Invoke actual callback wiring rather than a copied controller; label source assertions separately from mounted-home proof.

| Boundary held/failing | Interleaving | Required evidence |
| --- | --- | --- |
| Permission true/false/reject | end/cancel/dispose, then resolve; repeated start | Driver entry count; current bubble only; no inferred grant; disposed capture rejection observed |
| Temp lookup/sweep/start | end, cap, dispose in both orders | Joined completion; owned candidate/file; driver order; partial failure retained |
| Cap/native stop | release joins, repeated release, fresh start | One native stop, at-most-one exact file, no old file on later hold; failed stop not false idle |
| File read/send/delete | dispose/new hold/link absent; read/send/delete failure | Entered file ownership, later send/display fence, no false remote receipt; cleanup failure honest |
| Key token + ordinary legacy | each enters first, ordinary end before its permission | Exact token/file attribution; key stale zero effects; report winner question before activation |
| Semantics/gesture/space dispatch | repeated actions/long-press cancel/lifetime end | Actual callback dispatch plus held async work; no uncaught futures or invented cancel behavior |
| Request/phone intake | overlapping delivered files, Stop, malformed/oversize | Existing queue/intake protections remain; input identity not confused with runner ownership |

## Validation and limits

Unchanged nine-file targeted suite passed **228 tests**: [capture](../test/audio_capture_test.dart), [identity](../test/audio_capture_identity_test.dart), [key intent](../test/key_recording_intent_test.dart), [face semantics](../test/face_a11y_test.dart), [phone intake](../test/phone_audio_test.dart), [request runner](../test/request_runner_test.dart), [hold controller](../test/hold_key_controller_test.dart), [hold lifecycle](../test/hold_key_lifecycle_test.dart), [phone reply](../test/phone_reply_test.dart). Expected safe fixture diagnostics appeared; suite exited0. Actual driver/storage/player and channels are injected synthetic boundaries. No new fixture, native mic, mounted MacHome/phone/link permission proof or hardware run. These do not settle the proposed outer-caller matrix.

Attempted lookups for `phone_audio_intake.dart`, `ISSUE_ACCEPTANCE_MAP.md`, `face_screen_test.dart` and old plugin Classes paths missed. Located actual phone_audio.dart, ACCEPTANCE_MAP.md, face_a11y_test.dart and package Sources paths before deriving claims. Preview renderer availability is checked separately; a missing optional Python renderer is not a failed app validation. Local targets and full rendered preview are verified before PR. All30 local links/anchors passed. Initial preview had duplicate title and a
split table row; repaired renderer title/style and inspected the complete
updated preview. Exact-head required CI remains awaited until PR results. No issue effects or assignment changes follow.
