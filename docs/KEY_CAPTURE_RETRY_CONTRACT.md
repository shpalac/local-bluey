# Key capture retry contract proposal

Historical read-only proposal for [#413](https://github.com/shpalac/local-bluey/issues/413), inspected at main `57c1220eb6f253f63db82877fa37bc64a0113b40` on 11 October 2026. This page did not implement or authorize any mechanics. The source facts below describe that snapshot, not current APIs. Separately reviewed PR416/418/420/422 later delivered identity, release, key recovery and the cleanup action; see [current reconciliation](ACCEPTANCE_MAP.md). At this historical snapshot, [#391](https://github.com/shpalac/local-bluey/issues/391) still lacked explicit capture-uncertainty recovery. [#393](https://github.com/shpalac/local-bluey/issues/393) native validation is a separate owner-only decision.

## Decision needed

Keep the key owner fail-closed for now. A new key hold must not silently retry or clear uncertainty. The smallest credible recovery proposal is a **dedicated, explicit, no-delivery cleanup operation backed by an opaque capture-session token and an atomic capture-owned check/operation**. Current APIs cannot provide that evidence.

Manager must choose whether to prepare a bounded capture-identity/API and key-recovery implementation task, or keep current key containment pending a separately defined host restart/recreation lifecycle. Approval of this docs page does not approve either implementation, new UI, device work, or global face/key arbitration.

A generic `capture.stop()` retry guarded by `cleanupPending`, `isRecording` or a file path is unsafe. It can stop or consume a later ordinary-face recording between observation and entry. Clearing the key flag on wrapper-null is equally unsafe: null does not identify which session, if any, was cleaned.

## Current source facts

These are source/fixture observations at the historical57c1220 snapshot, not current APIs, proposed mechanics or native proof. Historical source links are pinned to that snapshot.

| Evidence | What it establishes | What it cannot establish |
| --- | --- | --- |
| [MacHome shared instance and callbacks](https://github.com/shpalac/local-bluey/blob/57c1220eb6f253f63db82877fa37bc64a0113b40/lib/main.dart) | `_keyRecording` receives the same `_capture` used by FaceScreen hold and local KeyboardListener space callbacks. Face/local-space releases call `_onHoldEnd`, then generic capture.stop and `_processUtterance` for a returned file. | Which input owns the current driver candidate or returned file. There is no shared input-owner token. |
| [KeyRecordingIntent](https://github.com/shpalac/local-bluey/blob/57c1220eb6f253f63db82877fa37bc64a0113b40/lib/services/key_recording_intent.dart) | Key-local session invalidates permission/publication; `_captureOwned` is set before capture.start, `_captureUncertain` on start/stop throw, and both `_cleanup`/`_stopOwned` refuse further stop under that flag. Pending key file deletion retains its exact File. | Key-local session/boolean is not AudioCapture session identity. Capture.start can return idempotently for another active capture, so successful return is not proof of acquisition. |
| [AudioCapture](https://github.com/shpalac/local-bluey/blob/57c1220eb6f253f63db82877fa37bc64a0113b40/lib/services/audio_capture.dart) | Private `_session` changes on actual `_start`; candidate is installed before driver.start after temp setup. Failed start/stop retains typed uncertainty. Cap/release join `_stopOp`; first release consumes `_pendingFile`. | No public opaque identity, input-owner evidence, per-session cleanup receipt or non-consuming cleanup API. `start` returns void and `stop` returns only File?/null. |
| Same capture getters | `cleanupPending` reports candidate/uncertainty/dispose failure/owned cleanup files; `isRecording` reports wrapper state; `debugPath` is test-only current/last path. | `cleanupPending` excludes `_pendingFile` awaiting release consumption. False is neither a file-ownership receipt nor permission to clear key uncertainty. `isRecording=false` can coexist with partial native open. Path is not identity. |
| [Actual key fixtures](https://github.com/shpalac/local-bluey/blob/57c1220eb6f253f63db82877fa37bc64a0113b40/test/key_recording_intent_test.dart) | Permission races, entered start/stop, exact delivery/delete ownership, retained partial-start/stop uncertainty and failed-delete explicit retry. Once capture uncertainty is set, tests expect no later driver stop/start or delivery. | No identity-backed recovery or external face-stop/fresh-face/stale-key-retry contract. Source audit is not mounted MacHome/device proof. |
| [Actual capture fixtures](https://github.com/shpalac/local-bluey/blob/57c1220eb6f253f63db82877fa37bc64a0113b40/test/audio_capture_test.dart) | Current-driver successful null differs from wrapper-only null; failed deletion is retryable without repeating stop; cap/release and close/delete joiners retain exact ownership; disposal success alone is not stop proof. | Which caller owns a session, or whether a stale key cleanup may safely touch a later face session. |

### Who can act between key failure and retry

- Key start/send/cancel/disposeIntent are serialized only by the key owner's tail. That queue does not serialize face/local-space calls.
- Ordinary face and local-space callbacks independently ask permission, start the shared capture, stop it and process a returned file. Their existing behavior is outside this task; it is not made safe by key-local generation checks.
- Capture's timer can stop the current candidate, leaving a file for a release caller. An external stop may consume it before key code sees anything.
- External current-driver cleanup can resolve capture uncertainty, after which an ordinary-face start can create another session while the key flag remains uncertain. A later blind key retry could target that new session.
- MacHome teardown removes the key listener, invokes closeCapture and attempts capture disposal. Key closeCapture caches one close future; repeated calls do not themselves retry failed close. AudioCapture.dispose has its own retryable disposal/cleanup contract but permanently rejects new starts on that instance.
- Phone intake and the iOS client's separate capture are not evidence of ownership for this MacHome instance. No phone/request source change is proposed.

## Two options

### A. Preserve fail-closed key uncertainty

Keep current behavior. Permission and exact-file-delete failures retain their existing recovery. Partial-start/stop uncertainty continues blocking fresh key starts, sends and key cleanup attempts; teardown still attempts shared capture disposal.

This avoids introducing a stale cleanup that stops a later face recording. It does **not** satisfy #391 explicit retry for capture uncertainty or prove native stop/erasure. App restart/recreation may create a fresh Dart owner, but it is not validated native cleanup: current teardown can fail and a new instance is not a stop receipt for the old one. Do not promise restart repairs the microphone without separate lifecycle/native evidence. A user-facing restart instruction or new recovery UI needs its own review.

### B. Identity-backed explicit cleanup

Proposed mechanics only. Method/type names are illustrative, not an API commitment.

1. **Acquire a capture-owned identity at attempted acquisition.** A key start requests an opaque token bound to this capture instance and its actual acquisition generation. The token must remain retrievable when temp/driver start fails, including before the start future rejects. Busy/idempotent start must report no acquisition rather than attaching a key claim to another input's capture. A token cannot be derived from the key session, timestamps or debugPath.
2. **Retain evidence across external completion.** The capture owner tracks a narrow terminal receipt for that token: current candidate unresolved, cleanup in progress, stopped with exact file ownership retained, file consumed by an external caller, closed/disposed, or superseded/unknown. Boolean absence and generic null are not receipts. Repeated receipt queries/cleanup cannot steal a file already consumed elsewhere.
3. **Check and enter atomically inside AudioCapture.** Explicit cleanup accepts the retained token. If it no longer owns the current candidate, it must not call current driver.stop or consume current-session output. Legacy face/local-space start/stop must participate in the same internal session mutation fence even if their public signatures stay unchanged. A prechecked token followed by generic stop is still a race. If this requires changes to cross-input scheduling or ownership policy beyond session-safe rejection, report that scope need before implementation.
4. **No delivery, no fresh start.** A successful matching current-driver cleanup may stop only the token's candidate, own only its recovered output and retained candidate files, delete them through observable retryable deletion, then return a token-scoped terminal receipt. Never call `_deliver`/`_processUtterance` from recovery. A fresh key hold is a later explicit action after verified Dart cleanup, not an automatic continuation.
5. **Join repeated recovery.** Install token-scoped pending ownership before notification. Identical concurrent retries join one completion through stop and file deletion. A retry remains pending while either is held; generic safe failure retains exact token/file uncertainty for another explicit attempt. File-only retry must not repeat confirmed driver stop.
6. **Separate lifecycle publication from cleanup.** Capture token identifies resource; key generation identifies whether status may publish. Cancel/fresh/dispose must not let a stale completion clear a newer key claim or publish late UI. A disposed key owner cannot be revived. Terminal receipts after capture disposal distinguish confirmed cleanup from disposal-only success; no new driver stop on a disposed instance without a separately reviewed lifecycle contract.

This option does not authorize global arbitration, cancel entered utterance processing, change cap timing, native-plugin contract, consent/privacy policy or face/phone UI. It does require a new capture API/internal identity contract and directly affected acquisition/release fencing, so it cannot be implemented as a key-only flag reset.

### Permitted recovery effects, if separately approved

- On positive matching ownership: join only that entered capture operation, attempt its current-driver cleanup, retain/delete only its exact owned files, publish a safe current retry result.
- On token mismatch/unknown ownership: zero driver stop, zero current-file consumption/deletion, zero delivery; keep unresolved result unless a positive terminal receipt accounts for the old token.
- On external file consumption: do not delete or deliver the externally owned file. Clear the old key claim only if the chosen contract positively accounts for the old resource and has no owned files left. External processing is not retroactively canceled.
- A receipt may mean "this Dart candidate was accounted for"; it must never mean native recording/physical erasure verified. #393 remains separate.

## Proposed deterministic test matrix

No tests below were added or run as new implementation evidence. Existing references show the available seam; missing rows are proposed acceptance for a future reviewed implementation.

| Case | Existing evidence | Required token-backed assertion |
| --- | --- | --- |
| Permission wait ended before start | Key entered-stage fixtures | No acquisition token/driver start; late result cannot create a candidate or cleanup another input. |
| Temp failure before driver entry | Capture pre-entry-temp fixture | Token outcome distinguishes no driver entry from partial driver entry; zero stop of another candidate. |
| Driver opens then start throws | Capture partial-start, key uncertainty fixtures | Retain exact token despite rejected start; explicit matching retry enters one stop; no delivery; fresh hold blocked until full cleanup receipt. |
| Failed stop remains open | Capture failed joiners/key failure fixtures | Failed retry retains token/typed uncertainty; later matching success deletes exact output; no flag-clear from wrapper state. |
| Successful driver stop returns null | Capture current-driver-null fixture | Positive receipt identifies actual driver operation/token and candidate file cleanup. Wrapper-only later null cannot substitute. |
| File deletion throws | Key exact delete retry/capture null-delete fixture | Retain exact file; retry deletes only that file; no second confirmed driver stop or delivery; settle after held deletion. |
| Capture cleanupPending false with pending release file | Source: getter excludes `_pendingFile` | False cannot clear token or consume/delete unaccounted file; explicit receipt must settle ownership. |
| Cap stop versus explicit cleanup/release | Existing #246 capture join fixtures | One stop; one file owner. Recovery never delivers; competing release receipt explicitly identifies consumption, not guessed success. |
| External stop completes old key candidate | Current generic stop/source only | Receipt names old token and whether output was consumed; key retry neither redelivers nor deletes transferred file. |
| External stop, then new face start, then old key retry | Not covered by current identity fixtures | Old token mismatch: zero stop of new candidate, zero consumption/deletion of its file, new face release remains functional. |
| New face start races after check but before cleanup entry | Not covered | Atomic capture fence prevents check-then-act on later generation; exactly one permitted target or safe rejection. |
| Key acquisition while face capture/start already active | Source start is idempotent | Explicit busy/no-acquisition result; never issue a key token for the face resource. Ordinary legacy behavior is not silently redesigned. |
| Repeated concurrent explicit retries | Existing join seams, no recovery API | Same token pending completion, one stop/delete attempt, incomplete before held release, shared safe result; no hanging/uncaught future. |
| Cancel/fresh key intent supersedes entered retry | Existing key generation seam | Old result cannot clear new token/status; owned old-file cleanup only; no automatic new start/delivery. |
| Dispose while cleanup entered; retry after driver disposal | Existing capture/key close fixtures | Join owned close where authorized, no late key notice/no revival; disposal-only success not stop receipt; mismatch never calls disposed/new driver. |
| Allowed=false/kill during retry | Existing permission/kill seam | Preserve kill semantics; no delivery/new start/current UI publication. Cleanup policy and permitted retained side effect explicitly selected, not inferred. |

All future fixtures must use actual shared AudioCapture and KeyRecordingIntent with injected RecorderDriver, gated entry/release and exact temp files, not call-count-only fake helpers. External face behavior can be represented by direct calls on the same actual capture for deterministic ownership tests; that is not mounted MacHome or native proof. Include focused/full current-head CI without weakening assertions, increasing sleeps or adding recurring/device runs.

## Unresolved boundaries and next step

1. **Contract authority:** manager chooses whether narrow session-identity cleanup is worth a separate implementation task, and what a positive externally-consumed terminal receipt permits. No such choice is made here.
2. **Compatibility:** capture-owned identity must reject a key acquisition that merely returns from another input's idempotent start. Atomic fencing may require touching capture acquisition/release internals or adapting direct callers. If it changes who wins input overlap rather than rejecting stale cleanup, it is broader arbitration and needs a separate scope decision.
3. **Lifecycle:** disposed drivers and failed shared teardown cannot be treated as restart recovery. Any driver recreation or shutdown retry changes lifecycle scope and must be reviewed separately.
4. **Outstanding acceptance:** #391 explicit capture retry stays partial until approved implementation/evidence. #393 requires owner-only native validation; deterministic receipts cannot close it. #351/#266/#344 and unpublished shpalac work remain untouched.

Next responsible owner: manager decides the bounded contract and assigns any future implementation; Northbeam maintains this proposal/map. No issue closure/status/assignee or source/test/UI changes follow from this page.
