# #441 explicit window action caller evidence

Refs #441 only. Base: 418a85c3dc263ac51af38c1e527e8c2e9e64c522.

## Contract and scope

The retained window_manager 0.5.2 operations are unchanged. Explicit tray Show and icon click share one caller. Successful show completion precedes focus; show failure prevents focus. Hide enters hide only. Completion/pending is installed before queued entry and notification. Same intent joins; conflicts retain one entered intent plus the latest explicit not-entered successor, with joined completion covering successors. No automatic retry, startup/status/rebuild window action or native-state claim is added.

Final intent failures become a generic local Show/Hide notice with explicit retry only. Pending action is disabled. The independent notice is in both existing MacNoticeRegion branches. It is not a guaranteed recovery surface while the window is hidden. Local returned completion does not prove actual native visibility or focus.

Manager decision: caller-level disposal fence, unchanged entered plugin work. Once windowManager.show is entered, its internal isMinimized/restore/show sequence may finish after caller disposal. Later caller focus and every not-entered successor are fenced, and late display is suppressed. This is not native cancellation or a guarded adapter.

No tray publication/menu/title/singleton/destroy, speech/player/phone, watch/safety/core, Settings/onboarding/tutorial owner edits or ownership transfer. #351/#266/#344 holds and #246/#393 native acceptance boundaries remain unchanged.

## Tests

- Direct caller: 28 passed. Actual window_manager MethodChannel with held isMinimized/restore/show/focus/hide, each failing step, no restore when not minimized, retry, duplicate completion identity, both conflict orders and bursts/latest successor, final error replacement, synchronous injected throws, queued/entered/reentrant disposal. Held isMinimized/restore fixtures explicitly prove entered plugin work may finish but no later focus/successor/display.
- Composed matrix: 32 passed. Actual caller/channel and WindowActionNotice alongside retained speech mute/host/hold-key/key-cleanup/permission/trust notices, actual FaceScreen and OnboardingScreen. Each case exercises Show failure/held retry/failure/retry success and Hide failure/retry success; other notices and body remain independent. EN/Hebrew RTL, 320/1000 widths, 1x/2x text scale, light/dark and both branches. Pending disabled, no overflow, real operation counts and reachable actions checked.
- All 140 sorted test files in four sequential 35-file batches: 424 + 476 + 645 + 456 = 2001 passed, one existing skip. Final batch rerun after retained mute/Hide composition: 456 passed. Final focused direct/composed: 60 passed.
- Analyze clean. Format lib/test: 248 files, zero changes. Diff check clean.

## Visual inspection

All 16 refreshed Show error/pending sheets directly inspected (128 top/action scroll-state views). All four refreshed Hide error-action sheets directly inspected (32 views). Three full originals also inspected: compact 2x EN normal Show error, compact 2x Hebrew onboarding Show error-action, regular EN normal success.

New localized text/action remains readable and scroll reachable, pending action disabled and separate from body/other notices. Local success removes only this notice. Existing compact 2x onboarding title/chip ellipses and viewport scroll clipping are retained, not redesigned. Scrolled top/action views are not claims that every notice is simultaneously on screen.

Regenerate with TRUST_PIXELS=1 FLUTTER_ROOT set to installed SDK and flutter test test/window_action_notice_test.dart. Pixel capture uses existing Roboto and installed Noto Sans Hebrew/MaterialIcons fonts. These are inspection artifacts, not golden snapshots.

## Attempts and limits

Initial analyze reported three constructor-formal and two brace style infos, fixed without changing the selected contract. Final focused/composed/full batches passed; no production failure was inferred from style findings. Main wiring assertions are source-only, not a mounted MacHome/native tray test. Channel fixtures do not prove OS window pixels, focus, hidden-window notice reachability or cancellation. Entered plugin internal steps can outlive disposal as selected by the manager. No issue disposition or auto-close requested.

## Images
- [441-1000-1-en-light-normal-success](441-1000-1-en-light-normal-success.png)
- [441-320-2-en-dark-normal-error-top](441-320-2-en-dark-normal-error-top.png)
- [441-320-2-he-light-onboard-error-action](441-320-2-he-light-onboard-error-action.png)
- [441-hide-sheet-00](441-hide-sheet-00.png)
- [441-hide-sheet-01](441-hide-sheet-01.png)
- [441-hide-sheet-02](441-hide-sheet-02.png)
- [441-hide-sheet-03](441-hide-sheet-03.png)
- [441-sheet-00](441-sheet-00.png)
- [441-sheet-01](441-sheet-01.png)
- [441-sheet-02](441-sheet-02.png)
- [441-sheet-03](441-sheet-03.png)
- [441-sheet-04](441-sheet-04.png)
- [441-sheet-05](441-sheet-05.png)
- [441-sheet-06](441-sheet-06.png)
- [441-sheet-07](441-sheet-07.png)
- [441-sheet-08](441-sheet-08.png)
- [441-sheet-09](441-sheet-09.png)
- [441-sheet-10](441-sheet-10.png)
- [441-sheet-11](441-sheet-11.png)
- [441-sheet-12](441-sheet-12.png)
- [441-sheet-13](441-sheet-13.png)
- [441-sheet-14](441-sheet-14.png)
- [441-sheet-15](441-sheet-15.png)
