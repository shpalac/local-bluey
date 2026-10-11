# Permission recovery observation (#429)

Base: main `977fa888d76fcf6b08338e3133a0891feec9195e`.

## Contract and boundaries

The retained caller defaults to the same actual `PermissionWatchdog.recheckRevoked`. Unknown, loading, current and failed describe the recovery observation, not a permission grant or native readiness. Failure retains the prior list and displays a generic unverified message. Explicit retries join one installed future, including actual baseline I/O. Resume bursts during an entered read request one sequential fresh successor; the shared completion covers successors and stale display is suppressed. Disposal fences queued source entry and late display, not entered owner work.

Main uses the same retained watchdog, startup, resume, listener and disposal routes. The selected recovery permission is captured at build time. Existing explicit Fix/Later content and `clearBaseline(selected id)` effects remain unchanged; caller dismissal only removes display and invalidates older entered list versions. A genuinely fresh read can report a new revocation according to the actual watchdog contract. Onboarding `recordGranted` is untouched.

**Not delete fencing:** entered watchdog baseline writes may outlive this caller or deletion. No watchdog, baseline, registry, deletion, settings, onboarding/tutorial owner, NativeControl/Swift, trust core, recording, face, phone, request or permission policy changes. Original shpalac #223-227/#247 ownership is not transferred. #351/#266/#344 holds, #246 shpalac and #393 native remain separate.

## Tests

- 16 direct caller fixtures: actual watchdog/checkers and preferences, each checker error, actual preferences read failure, held baseline write completion, retained error and fresh recovery, synchronous throw, held old error and resume bursts, original clearBaseline plus display dismissal, already-produced delayed list filtering, queued/entered/reentrant disposal, source-only main routing assertions.
- 32 composed widget cases: 320/1000 x 900, 1x/2x text, English/Hebrew RTL, light/dark, normal/onboarding. Actual permission caller/watchdog, failed TrustObservationNotice, HostReloadNotice, HoldKeyCallerNotice, KeyCleanupNotice, FaceScreen/OnboardingScreen, normal PermissionRecoveryCard. Tap retry, disabled pending, successful recovery, retained error, Fix/Later, trust/host/hold controls, enabled key cleanup, settings/close and onboarding check-again. Synthetic permission/settings/close callbacks do not prove native effects. Read checks never invoke permission prompting.
- Full recursive 134-file suite run sequentially in four root batches plus nested screenshot harness: 424 + 427 (one existing skip) + 599 + 404 + 24 = 1878 passes, one existing skip. The permission batch and final 48 focused cases rerun after self-review, along with clean analyzer and format/diff checks. No sleeps, added skips or assertion weakening.
- Preferences held-I/O fixture imports the already-resolved plugin interface with a narrowly commented transitive-package lint ignore, not a dependency change.

## Pixels and inspection

`PERMISSION_PIXELS=1 FLUTTER_ROOT=/tmp/flutter-local flutter test test/permission_observation_notice_test.dart --concurrency 1` generated seven states for each of 32 compositions. Sixteen sheets pair normal/onboarding states. Three originals retain readable compact English error, compact Hebrew pending and regular Hebrew error. All 16 sheets and all three originals inspected directly: new permission text/actions readable in English and RTL, independent failed trust notice visible, recovery card and controls reachable by scrolling, no overflow exceptions, notice region bounded to 405px. Screenshots record scroll position, not all controls simultaneously.

Existing onboarding heading/chip truncation at compact 2x remains unchanged; onboarding controls are scrollable and the check-again tap is tested. This is synthetic composition plus source assertions, not a mounted live Mac/real-device run or native permission proof.

## Failed attempts and repairs

Initial 32 visual cases failed an expectation: a held probe granted all permissions, then the fixture reverted other ids to false, so the actual watchdog correctly returned multiple revocations. Controlled grant values repaired to keep the intended other-id grants. Assertion retained; no production defect inferred. All 32 pixel cases then passed. Adding the independent failed trust notice required scoping duplicated Check status selectors. Final self-review captured main's selected permission at build time and added explicit unchanged Fix tap coverage before Later; all 48 focused fixtures passed.
