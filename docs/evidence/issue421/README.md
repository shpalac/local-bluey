# #421 explicit key cleanup caller evidence

This is synthetic Flutter widget evidence, not a mounted MacHome run, native
microphone readiness test, permission grant, physical erasure proof, or restart
claim. The exact MacHome imports, retained owner, kill/dispose wiring and both
notice placements were source-reviewed and asserted by a fixture.

`key_cleanup_caller_test.dart` has 22 actual caller + KeyRecordingIntent +
AudioCapture + injected RecorderDriver cases and exact synthetic temporary files.
They cover partial-start/stop uncertainty, concurrent/reentrant stop and deletion
completion, failure retry, queued/entered kill/dispose, notifier reentrancy,
no-entry, transferred external output with newer legacy recording, capture-owned
and separately key-owned deletion, disposed owner zero effects, normal live
recording ineligibility, and no automatic guard-change recovery.

`key_cleanup_notice_test.dart` has 32 composed matrix cases plus one rendered resume regression: 320/1000 logical-pixel widths,
900 height, 1x/2x text scale, English/Hebrew RTL, light/dark, and both branches.
The normal fixture uses actual FaceScreen with an independent request bubble;
onboarding uses actual OnboardingScreen with injected permission checks and mock
preferences. Both use the actual existing host/hold notices and new key notice.
The normal fixture also includes the unchanged cloud/accessibility banner content
and synthetic route settings/close controls. This is composition evidence, not
execution of MacHome's private state or native actions.

Tests scroll and tap host/hold retry, cleanup retry (failure then held retry and
success), accessibility action, settings/close or onboarding Check again. They
assert no overflow, no cleanup delivery or wake, disabled pending action,
retryable safe failure, and a notice region no taller than 45% of the viewport.
Main callbacks, request bubble, existing banner text/actions/visibility policies,
and capture core are unchanged. The manager-selected optional key recover
entry predicate is checked only before queued cleanup, preserving default
direct-owner and already-entered cleanup behavior. Scrolling is expected: screenshot edges may
show part of a neighboring banner. Success removes only the outstanding cleanup
notice; other notices remain independently visible.

The contact sheets show successive normal top, cleanup-aligned top, pending,
bottom action, success, and actual onboarding pending positions. Every matrix
combination is retained; selected compact Hebrew originals are also included.
1/2 in filenames means text scale, not device pixel ratio. Pixel generation uses
Roboto and local Noto Sans Hebrew fallback plus Flutter MaterialIcons; normal
CI tests load the bundled Roboto only and do not require local Hebrew fonts.

Reproduce the widget suite:

```sh
flutter test test/key_cleanup_caller_test.dart test/key_cleanup_notice_test.dart
FLUTTER_ROOT=/path/to/flutter KEY_CLEANUP_PIXELS=1 \
  flutter test test/key_cleanup_notice_test.dart
```

Pixel export requires `/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf`.
All output is synthetic; no captured user audio or private provider errors.

Validation: analyzer clean, format 229 files unchanged, diff whitespace clean.
All 130 test files passed in four non-overlapping sequential file batches:
674 passed/1 skipped, 518 passed, 258 passed, 331 passed = 1781 passed/1 skipped.
Earlier parallel runs shared build output and were discarded after native asset
manifest collision; interrupted partial batches were not counted as passes.
Current-head CI remains required before merge. Refs #421 and #391 only; issue
closure/acceptance disposition and #393 native owner checks remain separate.

## Self-review repairs

Two actual race failures were found before PR and reported to the manager.
The selected optional `recover(canEnter:)` predicate prevents queued retry
entry after caller disposal/kill during synchronous owner pending notification,
without changing default direct-owner recovery under kill. Caller failure/abort
evidence survives suppressed owner publication only while cleanupPending, and
is invalidated by fresh owner pending/acquisition. After kill-failed-stop, an
allowed-again caller re-enables the explicit action without automatic retry.
22 caller + 53 direct key + 32 composed cases pass; default direct-owner and
entered-cleanup regressions are included. Full passing counts above are reruns
after these repairs, not carryover from the earlier 1772 result.

Manager CHANGES #422 also found actual tray resume reset was non-notifying.
Main now refreshes only the cleanup guard immediately after the existing reset;
source regression asserts that ordering. The actual rendered notice is disabled
under kill, enabled after resume-refresh with zero new effects, then performs
cleanup only on an explicit tap. All 130 files rerun after this repair.
