# Acceptance reconciliation: #363, #366, #372

Docs-only note for issue #469. It maps each original acceptance bullet of the three open issues to what is on `main` today. It changes no code, issue, comment or assignee. #363 stays owner-retained whatever this note recommends.

Evidence here is synthetic: fake preference stores, fake authenticators, fake players and in-memory file systems. It is not proof of physical erase, OS behavior, real biometrics, a real phone or a real Mac.

Basis: `main` at `1a48797` (live repository read on 2026-10-11). The PR heads below were each approved by the manager at that exact head in the PR Slack thread. Squash merges and CI status were read from GitHub the same day; the required checks (static, test, linux, security) were green on all three PRs.

| Issue | PR | Approved head | Squash on main | Test files |
| --- | --- | --- | --- | --- |
| #363 app-lock clear | #364 | `6cb9b77841ba9bf44514fa1d3cca6abb3c63a22a` | `7c32618` | `test/biometric_lock_test.dart`, `test/lock_gate_test.dart` |
| #366 intake serialization | #370 | `997eb3a8338fd5dfa1596fc2caf803265c8ee874` | `d1e1020` | `test/request_runner_test.dart`, `test/phone_audio_test.dart` |
| #372 phone reply playback | #374 | `0485d361a564d1bacc50e56654f5ba5419a7bb21` | `104ac2c` | `test/phone_reply_test.dart`, `test/phone_reply_ui_test.dart` |

All three PRs used Refs, so none closed its issue.

## #363 App-lock preference clear

Source: `lib/services/biometric_lock.dart`, `lib/ui/app_lock_tile.dart`, `lib/services/data_registry.dart` (`app_lock_pref` clears through `BiometricLock.clearPreference()`).

| Original criterion | Delivered by | Status |
| --- | --- | --- |
| Persisted state loaded, explicit clear leaves storage absent, cached state false, tile updates without restart | `biometric_lock_test.dart` "clear removes storage and cached state and notifies"; `lock_gate_test.dart` "#363: clear updates the tile and drops a stale enable" | Met (synthetic) |
| Held enable authentication, clear, release old success: nothing persisted or published; fresh enable needs new auth and works | `biometric_lock_test.dart` "an enable authentication entered before clear is discarded"; the widget test above | Met (synthetic) |
| Held write and removal ordering; failed removal reaches the caller and retry works; no real OS fault claim | "clear is ordered after a write already entered", "a write queued after clear is dropped", "entered removal retains the real preference until it fails", "a false-return removal is a failure and retry works" | Met (synthetic) |
| Actual widget fixture for tile and clear, stale auth, fresh recovery; existing lock fixtures kept | `lock_gate_test.dart` "#363: registry clear route reports failure safely and recovers"; existing lock-off, failure and retry, lifecycle and bilingual tests unchanged | Met (synthetic) |
| Pixels inspected if UI changes | `docs/evidence/issue-363-applock-clear-failed-en.png`, `docs/evidence/issue-363-applock-clear-recovered-he.png` | Met |
| Failed authentication must not disable an enabled lock | "failed authentication does not disable an enabled lock" | Met |

Unmet original bounded criteria: none found.

Limits: no native biometrics, no real preference-file erase, no device. Those were never part of the bounded criteria and are not added as new gates.

Recommended disposition: ready to close as delivered at the synthetic level. #363 is owner-retained, so the owner decides.

## #366 Request intake

Source: `lib/services/request_runner.dart`, `lib/services/phone_audio.dart`, the `_onPhoneRequest` wiring in `lib/main.dart`.

| Original criterion | Delivered by | Status |
| --- | --- | --- |
| Malformed base64 and oversize `holdAudio`: safe message, no unhandled exception, no temp file | `phone_audio_test.dart` "malformed base64 is refused without a file or raw error text", "oversized payloads are refused before and after decoding", "malformed, oversize and non-audio give one safe bubble each" | Met (synthetic) |
| Write failure cleans up and reports once | "a write failure is reported once and leaves no file", "an entered partial write is removed and reported once", "a storage failure is one safe bubble and no leftover" | Met (synthetic) |
| Overlapping `process` calls never interleave; second is queued or rejected; UI reflects the active run | `request_runner_test.dart` "overlapping utterances run one at a time, in order", "beyond the queue cap a request is rejected and cleaned up" | Met (synthetic) |
| Stop during a queued request clears the queue | "Stop discards queued requests instead of running them", "a Stop between turn grant and entry revokes the request" | Met (synthetic) |
| #305 and #306 stop and deadline tests still pass | Existing tests in `request_runner_test.dart` unchanged and part of the full suite at the approved head | Met |

Unmet original bounded criteria: none found.

Delivered limits: queue cap is 2 (`maxQueued`); the phone payload bound is 8 MiB (`PhoneAudioIntake.maxBytes`), which is tighter than the 16 MiB link frame cap named in the issue. The container check only looks for a plausible MP4 container and does not validate audio. A second utterance during a run now waits, or is rejected beyond the cap with a Busy bubble; this was called out in the PR as a behavior change.

Recommended disposition: ready to close as delivered at the synthetic level.

## #372 Phone reply playback

Source: `lib/services/phone_reply.dart`, the phone section of `lib/main.dart`, the bubble note in the existing reply bubble.

| Original criterion | Delivered by | Status |
| --- | --- | --- |
| Malformed, empty, oversize audio; create, partial-write and player-start failures: no uncaught error, safe text, no false playing or done | `phone_reply_test.dart` "malformed, empty and oversize audio: safe note, no false receipts", "create failure, entered partial write: safe note, no leftover", "a player start error is one safe note, no playing, clip removed" | Met (synthetic) |
| Success and text-only receipt semantics; completion subscribed before play; immediate completion not lost | "success: playing after start, done on completion, clip removed", "an immediate completion inside play is not lost", "text-only replies are acknowledged by display, no session", "completion while play is held: playing then exactly one done" | Met (synthetic) |
| Held operation then newer say, stopSpeech or disposal: no old restart, receipt or late UI callback; unique clip ownership | "a newer say replaces a held one: no old receipts or leaks", "a late event from the replaced clip cannot finish or delete the new one", "stopSpeech stops playback, removes the clip, no later done", "stopSpeech during a held write: nothing starts", "dispose during staging: no play, no UI, no leaked clip", "dispose while playing: late completion sends nothing" | Met (synthetic) |
| Cleanup on completion, replacement and dispose; delete failure observable and retried; no physical erase claim | "a failed delete is observable and retried", "many entered clips: replaced or stopped, every waiter settles" | Met (synthetic) |
| Actual listener wiring plus extracted listener fixtures | "listener path: errors from callbacks never escape" | Met (synthetic) |
| Pixels inspected if rendering changes | `docs/evidence/issue-372-reply-cleanup-pending.png`, `docs/evidence/issue-372-reply-error-note.png`, `test/phone_reply_ui_test.dart` | Met |

Unmet original bounded criteria: none found.

Delivered limits: decoded reply audio is bounded at 12 MiB (`PhoneReplyReceiver.maxBytes`). Audio stays opaque; no codec validation is claimed. Latest say replaces the earlier one. Fake storage and player only: no real phone, Mac or speaker claim, and no new protocol message.

Recommended disposition: ready to close as delivered at the synthetic level.

## What this note does not claim

- No native, hardware, OS or physical-erase proof for any of the three.
- No statement about #268, #351, #344 or #160.
- No change to issue state. Closing any of these is a manager or owner action.
