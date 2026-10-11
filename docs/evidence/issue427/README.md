# Accessibility observation evidence

Synthetic injected probes and actual retained widgets, not real macOS permission or mounted MacHome proof. Main startup/resume/dispose and both notice branches are source-asserted in trust_observation_test.dart. Actual MacHostControl and NativeControl MethodChannel mocks cover true/false/null mapping and errors without permission requests/settings calls. Observations do not authorize tools.

## Completion contract

Startup/explicit checks join one installed pending completion. Resume during an entered read requests at most one fresh successor; resume bursts coalesce. The same completion waits through successors, older results/errors are not published. Resume before source entry joins that queued read. A further resume during a successor can request the next fresh read, still one sequential probe and one boolean latch, not an unbounded queue. There is no automatic retry after failure. Pending is installed before synchronous notification; queued disposal prevents source entry and entered disposal suppresses later publication/successor. Deferred notifier disposal supports listener disposal during notification.

Historical lastObservation is retained on failed checks, but current status is failed/unverified. The notice remains visible even after an earlier true result. Verified false alone offers the explicit existing askPermission then openAccessibilitySettings route; status checks never call either. The settings callback's existing error behavior is unchanged, not newly claimed safe.

## Render matrix

32 composed test cases:320/1000x900,1x/2x text, English/Hebrew RTL, light/dark, normal/onboarding. Seven sequential captures per case: unknown, error, denied top, denied action, pending, recovered, failed after previous grant. Sixteen sheets pair normal and onboarding rows with columns in that order. Scrolled captures show successive viewports, not simultaneous visibility of all notices. Each notice remains in the existing45%-height scroll region, body independent. Actual retained HostReload/HoldKey/KeyCleanup notices, FaceScreen/OnboardingScreen and PermissionRecoveryCard are composed. Settings/Close counters and injected permission fix/dismiss are synthetic. Tests tap status/denied settings, other retry/settings/close/permission Later or onboarding verify actions and assert no overflow or automatic capture effects.

All16 sheets and three originals were opened and inspected. Compact2x labels can require scrolling; capture transitions preserve readable wrapped text and controls. Existing onboarding titles/status chips truncate under2x as before; tested actions can be scrolled into view. Hebrew font/Roboto/material icon files loaded for pixels. Three original PNGs accompany sheets for compact denied-action, compact Hebrew pending and regular Hebrew error inspection. No native Hebrew wording review claimed.

## Validation and failed attempts

17 caller/channel fixtures and32 notice fixtures passed. All132 unit/widget test files ran sequentially in five batches:411+416+579+400+24=1830 passes and one existing model-store skip. No failed full batch discarded. Final49 focused tests passed after a test-only braces/format repair, analyzer clean and format233 unchanged; current-head required CI is separately reviewed before merge.

Initial32 composed notice tests passed. Adding actual PermissionRecoveryCard control checks used the wrong Dismiss selector, causing16 normal-route fixture failures. Corrected to its actual retained Later/מאוחר יותר action and reran all32 successfully with pixels. Later analyzer reported one test if statement needing braces; repaired and reran49 focused cases. No production error was concealed, no test assertions weakened, no sleep used for trust operation entry.

No HostControl/NativeControl/Swift, watchdog/baseline/deletion, onboarding/tutorial/Settings core, recording/capture/privacy/watch/consent policy changes. Remaining426 audit paths and shpalac ownership are separate. No OS grants, device readiness or #393/#246 acceptance follows from these fixtures.
