# #439 local mute caller evidence

Refs #439 only. Base: d55db6295c56fc1dd27e0fb07bb7837ec5e42cde.

## Contract and scope

The retained SpeechService.stop is entered immediately after the caller installs its completion. Duplicates join that completion through actual stop/release work; each explicit mute event still immediately broadcasts stopSpeech, including duplicates and notice retry. Sync/async local stop failures are consumed into a generic local error. Retry is explicit only. Caller disposal fences new entry and late publication before the unchanged terminal disposal call.

The local pending/error notice is independent in both existing MacNoticeRegion placements. Pending action is disabled; local success hides only this notice. It does not prove remote mute receipt or all-file erasure. SpeechService/player/storage/native/phone protocol, tray singleton/window, watch/safety and Settings/onboarding/tutorial owners are unchanged.

Source review: PhoneServer.broadcast remains synchronous and LineConnection.send retains its existing write-failure handling. The helper does not change remote-send policy or claim delivery from a broadcast count.

## Tests

- Direct caller: 12 cases. Actual SpeechService with controlled storage/playback, held stop/release, error cleanup, explicit retry, best-effort delete uncertainty, older resolve/write/start, terminal disposal and immediate invalidation. Injected operations cover synchronous throw, duplicate/reentrant identity, notification disposal and lifetime fencing.
- Existing terminal caller plus new direct caller: 22 passed.
- Composed matrix: 32 passed. Actual SpeechService, SpeechMuteNotice, retained other notices, FaceScreen and OnboardingScreen. 320/1000 widths, 1x/2x text scale, EN/Hebrew RTL, light/dark and both branches. Checks real retry counts/timing, held pending/disabled action, failure then success, reachable other actions, independent body and no overflow.
- Full sorted suite: all 138 files, four sequential batches of 35/35/35/33 files. 424 + 476 + 645 + 396 = 1941 passed, one existing skip.
- Analyze clean. Format lib/test: 244 files, zero changes. Final focused 54 passed; diff check clean.

## Visual inspection

All 16 sheets inspected directly. Each sheet contains eight error/pending top/action scroll-state originals, sorted by width, text scale, language, theme and branch. 128 action/top views total. The three attached full originals were also inspected: compact 2x EN normal error, compact 2x Hebrew onboarding error-action, regular EN normal success.

New text and retry are readable, scroll reachable, and separate from the request bubble/body. Pending action remains disabled. Success removes this notice while other notices stay. Existing compact 2x onboarding title/chip ellipses and viewport scroll clipping are unchanged; this is not an onboarding redesign.

Regenerate with TRUST_PIXELS=1 FLUTTER_ROOT set to the installed SDK and flutter test test/speech_mute_notice_test.dart. Pixel capture loads the existing Roboto asset and installed Noto Sans Hebrew/MaterialIcons fonts. Generated /tmp/439-* originals are not golden snapshots.

## Attempts and limits

Early composed attempts stalled because an actual SpeechService ordered future tail was created in the widget fake-async zone, then awaited in runAsync. Creating the actual owner and entering explicit taps in the real async zone repaired the fixture. One nullability compile error was repaired. Narrow timeout attempts and temporary debug prints are not evidence of a production bug; debug prints were removed. Final matrix passed without sleeps, skips or weaker assertions.

This is controlled IO/widget and source-wiring evidence, not mounted Mac tray, OS/player/device or remote receipt proof. Best-effort delete failure can coexist with local stop completion and is not erasure proof. #351/#266/#344/#246/#393 boundaries remain unchanged. No issue disposition or auto-close requested.

## Images

- [439-1000-1-en-light-normal-success](439-1000-1-en-light-normal-success.png)
- [439-320-2-en-dark-normal-error-top](439-320-2-en-dark-normal-error-top.png)
- [439-320-2-he-light-onboard-error-action](439-320-2-he-light-onboard-error-action.png)
- [439-sheet-00](439-sheet-00.png)
- [439-sheet-01](439-sheet-01.png)
- [439-sheet-02](439-sheet-02.png)
- [439-sheet-03](439-sheet-03.png)
- [439-sheet-04](439-sheet-04.png)
- [439-sheet-05](439-sheet-05.png)
- [439-sheet-06](439-sheet-06.png)
- [439-sheet-07](439-sheet-07.png)
- [439-sheet-08](439-sheet-08.png)
- [439-sheet-09](439-sheet-09.png)
- [439-sheet-10](439-sheet-10.png)
- [439-sheet-11](439-sheet-11.png)
- [439-sheet-12](439-sheet-12.png)
- [439-sheet-13](439-sheet-13.png)
- [439-sheet-14](439-sheet-14.png)
- [439-sheet-15](439-sheet-15.png)
