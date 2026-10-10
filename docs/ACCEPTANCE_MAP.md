# Refs-only acceptance map

Snapshot: main `975ad4e626c8fef85eba49f1399a23d8965ddeff`, 11 October 2026. Scope: [#411](https://github.com/shpalac/local-bluey/issues/411). All eleven issues below were OPEN when checked. This page recommends dispositions; it does not close issues, change ownership, or decide policy.

## Reading the evidence

- **Ready for manager disposition** means no unmet original bounded criterion was identified from the current source, committed fixtures/evidence and successful exact-head checks. It is not a closure, native readiness claim, or proof that every app workflow works.
- **Deferred** names an original criterion that still lacks evidence. Non-goals, native exclusions and broader startup limits are not extra acceptance gates.
- Independently checked for this reconciliation: live issue bodies/comments, merged PR state/head/merge, required check results, current source and fixture assertions, repository evidence targets, and selected complete visual samples. Historical local test totals and full image-inspection claims remain worker reports unless explicitly verified below. No new native/device run was performed.
- Source and test links resolve within this snapshot. Evidence READMEs and PNGs are historical artifacts, not live-system proof. Preserve them; use the follow-up references below where they describe a defect since repaired.

## Disposition summary

| Issue | Proposed disposition | Exact remaining criterion | Next responsible owner |
| --- | --- | --- | --- |
| [#379](https://github.com/shpalac/local-bluey/issues/379) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#391](https://github.com/shpalac/local-bluey/issues/391) | Partial / unresolved | "Explicit retry after failure" cannot recover retained capture uncertainty through the key owner. | Manager decides bounded recovery contract/next task; Northbeam keeps map current. |
| [#393](https://github.com/shpalac/local-bluey/issues/393) | Deferred | Native recorder semantics remain unverified, explicitly required by original issue. | Owner-only native validation decision; no device/permission work authorized. |
| [#395](https://github.com/shpalac/local-bluey/issues/395) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#397](https://github.com/shpalac/local-bluey/issues/397) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#399](https://github.com/shpalac/local-bluey/issues/399) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#401](https://github.com/shpalac/local-bluey/issues/401) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#403](https://github.com/shpalac/local-bluey/issues/403) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#405](https://github.com/shpalac/local-bluey/issues/405) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#407](https://github.com/shpalac/local-bluey/issues/407) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#409](https://github.com/shpalac/local-bluey/issues/409) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |

## Verified delivery ledger

Each PR below is MERGED. All four required checks (`static`, `test`, `linux`, `security`) independently returned SUCCESS for its head. Check links below are observed GitHub job URLs, not inferred links.

- [PR380](https://github.com/shpalac/local-bluey/pull/380)
  - Head: `046c9f89ddf3958391432528e5b50172bb3f1cab`
  - Main merge: `2d07f31c933a3054e55d41aea69cb6605f707822`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38062127460/job/114242345890) / [test](https://github.com/shpalac/local-bluey/actions/runs/38062127460/job/114242345831) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38062127460/job/114242345867) / [security](https://github.com/shpalac/local-bluey/actions/runs/38062127460/job/114242345849)
- [PR382](https://github.com/shpalac/local-bluey/pull/382)
  - Head: `4402faa7da44902cb2dbb6ef28ab19bef1451d60`
  - Main merge: `c6b751cabb33347d3f9fa5f9129055fe3bb5fca1`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38063430297/job/114246146487) / [test](https://github.com/shpalac/local-bluey/actions/runs/38063430297/job/114246146521) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38063430297/job/114246146606) / [security](https://github.com/shpalac/local-bluey/actions/runs/38063430297/job/114246146550)
- [PR392](https://github.com/shpalac/local-bluey/pull/392)
  - Head: `bb05b3bec51e5911dfd42e106b71745b6d1cd1eb`
  - Main merge: `04dd3f862009fb37737477a4a970678d1d97d115`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38072497879/job/114272821522) / [test](https://github.com/shpalac/local-bluey/actions/runs/38072497879/job/114272821478) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38072497879/job/114272821498) / [security](https://github.com/shpalac/local-bluey/actions/runs/38072497879/job/114272821434)
- [PR394](https://github.com/shpalac/local-bluey/pull/394)
  - Head: `99026ca8e0fa0e8b20e1b6aa9b86ae2d9fbe25d4`
  - Main merge: `872a07cfe432834364e419ca5c869b04b7edc846`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38075955174/job/114283021310) / [test](https://github.com/shpalac/local-bluey/actions/runs/38075955174/job/114283021326) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38075955174/job/114283021410) / [security](https://github.com/shpalac/local-bluey/actions/runs/38075955174/job/114283021301)
- [PR396](https://github.com/shpalac/local-bluey/pull/396)
  - Head: `f335a807a9fa4bb916d783f039c4cc2731c481e2`
  - Main merge: `407225a2349049320cc32823e25a45cc5c140602`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38077290302/job/114286820105) / [test](https://github.com/shpalac/local-bluey/actions/runs/38077290302/job/114286819747) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38077290302/job/114286820003) / [security](https://github.com/shpalac/local-bluey/actions/runs/38077290302/job/114286819840)
- [PR398](https://github.com/shpalac/local-bluey/pull/398)
  - Head: `0a57f2605d7148b9aa1c8f726b54f52033f2a8bc`
  - Main merge: `a7638aea9f3f4613a59b621c3b9b1f616583cba3`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38078866602/job/114291836122) / [test](https://github.com/shpalac/local-bluey/actions/runs/38078866602/job/114291836102) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38078866602/job/114291836074) / [security](https://github.com/shpalac/local-bluey/actions/runs/38078866602/job/114291836065)
- [PR400](https://github.com/shpalac/local-bluey/pull/400)
  - Head: `f6a08f20dbe990b3dd9fffc8bd4af5bd2a26f45e`
  - Main merge: `31c2fb109ab6a8602e64c46028e4add7afc1bcfd`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38080475771/job/114296169801) / [test](https://github.com/shpalac/local-bluey/actions/runs/38080475771/job/114296169800) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38080475771/job/114296169638) / [security](https://github.com/shpalac/local-bluey/actions/runs/38080475771/job/114296169820)
- [PR402](https://github.com/shpalac/local-bluey/pull/402)
  - Head: `c7e3f40503bbfc2b08c1fa6e17dd88a998676e67`
  - Main merge: `e9a7db29ba204a9a8777c4b3affb9ec5d89b8681`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38081538125/job/114299290703) / [test](https://github.com/shpalac/local-bluey/actions/runs/38081538125/job/114299290695) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38081538125/job/114299290701) / [security](https://github.com/shpalac/local-bluey/actions/runs/38081538125/job/114299290751)
- [PR404](https://github.com/shpalac/local-bluey/pull/404)
  - Head: `f9993a9c0743228e29f8adf79d965838de08df5c`
  - Main merge: `397cebb77d612cc84cd7d5a7aab70c458a5e978c`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38083145289/job/114304022362) / [test](https://github.com/shpalac/local-bluey/actions/runs/38083145289/job/114304022243) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38083145289/job/114304022439) / [security](https://github.com/shpalac/local-bluey/actions/runs/38083145289/job/114304022471)
- [PR406](https://github.com/shpalac/local-bluey/pull/406)
  - Head: `7707a05d299a54740759ab83f66e24fa84705b3f`
  - Main merge: `e4bbd44a2c299c2ace2dc1240a734e32bebb5216`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38084615883/job/114308439855) / [test](https://github.com/shpalac/local-bluey/actions/runs/38084615883/job/114308439897) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38084615883/job/114308439769) / [security](https://github.com/shpalac/local-bluey/actions/runs/38084615883/job/114308439785)
- [PR408](https://github.com/shpalac/local-bluey/pull/408)
  - Head: `b2929b40bbfba6b6b26a3d369d73421d3efcd6f3`
  - Main merge: `a9790551aff518f3d58abf01c65d8526eaa55126`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38085642785/job/114311440981) / [test](https://github.com/shpalac/local-bluey/actions/runs/38085642785/job/114311440978) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38085642785/job/114311441109) / [security](https://github.com/shpalac/local-bluey/actions/runs/38085642785/job/114311441063)
- [PR410](https://github.com/shpalac/local-bluey/pull/410)
  - Head: `c9ee1acad4bd4c01b0be87d101417511893281f8`
  - Main merge: `975ad4e626c8fef85eba49f1399a23d8965ddeff`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38086620927/job/114314356064) / [test](https://github.com/shpalac/local-bluey/actions/runs/38086620927/job/114314356262) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38086620927/job/114314356253) / [security](https://github.com/shpalac/local-bluey/actions/runs/38086620927/job/114314356338)

## Criterion reconciliation

### #379 Local-only preference ordering and Settings

Delivered: PR380 ordered read/write/clear ownership, safe uncertainty and actual Settings publication; PR382 contained the reported BrainHost caller gap; PR408 repaired that caller's retry completion.

Original acceptance coverage:

- False/throw toggle, retained state, explicit recovery and preserved unrelated edits: [actual Settings fixture](../test/privacy_clear_widget_test.dart), [Settings source](../lib/ui/settings_screen.dart).
- Entered read/write/remove versus registry clear, stale publication and fresh later choice: [ordering fixtures](../test/privacy_ordering_test.dart), [ordered owner](../lib/services/privacy_guard.dart), [registry entry](../lib/services/data_registry.dart).
- Read/remove failure retains honest state and propagates safe failure without fabricated OFF/rollback/erasure: the same owner/fixtures. STT/TTS/diagnostic fixtures assert zero HTTP effects on read uncertainty.
- Existing policy/regressions and full current-head checks: PR380 ledger; later PR410 full test check covers current main. [Failed](evidence/issue-379-local-only-failed.png), [cleared](evidence/issue-379-local-only-cleared.png), [recovered](evidence/issue-379-local-only-recovered.png) and [unverified](evidence/issue-379-local-only-unverified.png) Settings pixels are committed synthetic proof.

Unmet bounded criterion: none identified. Ready for manager disposition. The PR380 report's unobserved main BrainHost calls were subsequently contained by [host caller](../lib/services/host_reload_controller.dart) and [source-wiring fixtures](../test/host_reload_controller_test.dart), not left as new work. Retained remote-provider behavior after a failed privacy read is a separate policy limit, not solved by containment; no real-egress claim.

### #391 Key-only recording intent

Delivered: PR392 permission/session/file owner and distinct key main wiring; PR394 repairs the underlying Dart capture-contract remainder; PR396 observes separate hold-key lifecycle callers.

Original acceptance coverage:

- Permission/start/stop versus send/cancel/fresh/dispose in both orders: [key fixtures](../test/key_recording_intent_test.dart) enter actual AudioCapture with injected driver; current session checks in [key owner](../lib/services/key_recording_intent.dart) reject stale pre-start permission results.
- At-most-once current file delivery, canceled-file cleanup, retained failed-delete/start/stop uncertainty: those fixtures assert exact delivery/ownership, closeCapture and cleanupPending, not a native-stop guarantee. Explicit recovery works for permission/file-delete failure; it is not delivered for retained capture uncertainty.
- Kill/reset, overlapping key intents, stale/current errors and lifecycle UI containment: same owner/fixtures plus [key main wiring](../lib/main.dart). The source audit preserves ordinary face/phone paths.
- Actual shared owner/source-only main proof, existing regressions and required CI: PR392/394/396 ledger. [Widget fixture](../test/key_recording_pixels_test.dart) and [failure/pending/recovery/uncertainty evidence](evidence/issue391/README.md) use actual FaceScreen with synthetic owner, not mounted MacHome.

Exact unmet original criterion: "explicit retry after failure" remains partial for capture uncertainty. Current `_stopOwned` and `_cleanup` throw immediately while `_captureUncertain`; key start/cancel/disposeIntent cannot reach underlying capture.stop for a fresh current-driver cleanup attempt after partial-start/stop failure. The failure fixture explicitly expects later key starts to keep throwing after the fake driver failure is removed. Safe retention is delivered, but explicit capture-uncertainty recovery is not. **Partial / unresolved, manager decision next** on the bounded recovery contract and responsible implementation task. Do not widen source in this docs task or substitute a native gate for this Dart gap.

The historical issue391 README describes the pre-394 AudioCapture defect; current [capture source](../lib/services/audio_capture.dart) owns the candidate before driver.start and supports explicit current-driver cleanup. That underlying repair is delivered and should not be duplicated, but it does not automatically clear or recover the key owner's retained uncertainty. #393's native condition is separate. Shared face/key arbitration and cancellation of already-entered processing were explicitly excluded and reported, not newly imposed acceptance gates.

### #393 Partial-start and failed-stop capture contract

Delivered: PR394 candidate ownership before entered driver.start, typed retained uncertainty, joined cap/release/close and exact file-cleanup ownership.

Original evidence coverage:

- Partial open/throw; entered start versus stop/dispose; failed-still-open stop versus fresh start/retry/dispose: [actual capture fixtures](../test/audio_capture_test.dart) and [capture source](../lib/services/audio_capture.dart).
- Cap/release/retry joiners, exact-once delivery, timer-error containment, failed retry retention and explicit cleanup: same fixtures preserve #246 cap tests.
- Pre-entry temp failure, failed disposal, successful current-driver null versus wrapper-only null and joined owned-file deletion: same fixtures; [wake regressions](../test/wake_word_test.dart) retain failed-open uncertainty. PR394 required checks all passed.

Exact unmet original condition: "issue acceptance stays open if native semantics remain unverified." Successful injected `driver.stop`, including a returned null, resolves the Dart contract; production record-plugin partial-open/stop/disposal semantics have no native validation in this evidence. Deferred. Native validation is an owner-only decision; no device/permission work is authorized or assigned by this map. Current issue assignee remains Northbeam, with manager tracking the dependency and awaiting owner disposition. No native mic, physical-erasure, #246 closure or relaxed key-owner guarantee follows from deterministic tests.

### #395 Hold-key lifecycle caller observation

Delivered: PR396 shared caller for startup load, listener sync and close plus independent notice.

Original evidence coverage:

- Actual HoldKeySettings/Controller with fake entered read/permission/enable/disable/close, fresh OFF invalidation, stale/current/disposed, coalesced fresh-load retry and contained sync/async failures: [caller fixtures](../test/hold_key_caller_test.dart), [caller source](../lib/services/hold_key_caller.dart).
- Same helper in startup/listener/close and independent normal/onboarding notice placement: source assertions in that fixture and [main](../lib/main.dart).
- Complete synthetic failure/disabled retry/recovery notice: [widget fixture](../test/hold_key_caller_notice_test.dart), [evidence](evidence/issue395/README.md). Existing hold/key/capture regressions and full checks: PR396 ledger.

Unmet bounded criterion: none identified. Ready for manager disposition. Retained enabled/unverified preferences and uncertain native cleanup are unchanged owner semantics that the issue required us to report, not fix. Returned caller success does not imply real permission, enabled shortcut, recording readiness or stopped bridge; no mounted MacHome proof.

### #397 Appearance-only startup caller

Delivered: PR398 appearance containment/main wiring/notice; PR400 repairs the separately reported banner defect; PR410 adds pre-notification lifecycle/latest guards.

Original evidence coverage:

- Actual ThemeController read failure/reconciliation/fresh retry/stale/disposed and contained sync/async failures: [appearance fixtures](../test/appearance_startup_test.dart), [caller source](../lib/services/appearance_startup.dart).
- Exact last-theme-load main helper/order, retained mode without verified-storage/reset claim, independent app notice: source audit and [main](../lib/main.dart), [notice](../lib/ui/appearance_startup_notice.dart).
- Actual LocalBlueyApp/shared notice failure/disabled retry/recovery: [app fixture](../test/appearance_app_pixels_test.dart), [notice fixture](../test/appearance_startup_notice_test.dart), [historical evidence](evidence/issue397/README.md). Required theme/settings/deletion/full checks: PR398/410 ledger.

Unmet bounded criterion: none identified after follow-ups. Ready for manager disposition. Historical issue397 PNGs show invisible Stop/covered AppBar; PR400 and [current banner evidence](evidence/issue399/README.md) supersede that defect. Broader earlier startup/security/windowManager failures and native startup are explicit exclusions, not a whole-startup gate imposed on this caller.

### #399 WatchBanner Stop visibility and reserved route space

Delivered: PR400 banner-local light/dark palette and reverse-column reserved placement, preserving countdown, wording, Stop action and semantics.

Original evidence coverage:

- Actual LocalBlueyApp synthetic active watch/pushed route; 320/390 width, scales 1/1.5/2, EN/Hebrew RTL, light/dark, independent appearance failure/entered retry/recovery: [visual fixture](../test/watch_banner_visual_test.dart), [72-pixel evidence and four sheets](evidence/issue399/README.md).
- Visible Stop/back/body, actual contrast threshold and minimum 48x48 geometry: that fixture and [banner source](../lib/ui/watch_banner.dart). It taps back and exact Stop and verifies the synthetic session ends; [existing status-card semantics fixture](../test/home_status_cards_test.dart) is retained.
- Full banner/app/watch/appearance regressions: PR400 required checks and later PR410 test SUCCESS. Local historical timing failures/count conflict are recorded below, not erased by later success.

Unmet bounded synthetic visual criterion: none identified. Ready for manager disposition. Original wording "Refs-only if native/actual lock acceptance remains" is conditional, while the evidence scope explicitly forbids synthetic route labels as native biometric/watch proof. No separate unmet real-lock criterion is specified in #399; manager should identify a distinct task if that broader acceptance is intended. No native-watch/biometric guarantee or #351 consent-policy decision. AppBar titles may ellipsize at 320dp/2x; back remains operable.

### #401 Test-only wake lifecycle cleanup observation

Delivered: PR402 changes only wake_word_test.dart, with actual service/capture fake-driver cleanup gates and settled teardown.

Original evidence coverage:

- Start failure before/after partial open publishes lastError while cleanup/listening remain pending: [wake fixtures](../test/wake_word_test.dart) hold stop entry/release, assert joined service.stop stays incomplete, then assert exact file removal, cleanupPending=false, listening=false/open=0 and fresh restart maxOpen=1 without scoring/transcription/wake.
- Window-delay failure has a different order: stop enters before error publication. Adjacent score/transcriber/failed-stop fixtures join service.stop before final assertions; tracked services/captures and isolated temp directories settle before teardown.
- Focused complete wake/capture/key regressions were reported as 102 passing. Local all-in-one run interrupted at 959/one skip is **not** a full pass. The missing full current-head evidence is independently supplied by [CI run 38081538125](https://github.com/shpalac/local-bluey/actions/runs/38081538125), verified `run_attempt=1`, head `c7e3f40503bbfc2b08c1fa6e17dd88a998676e67`, conclusion success; all required PR402 checks passed.

Unmet bounded test-only criterion: none identified. Ready for manager disposition. Production semantics were not changed; no increased sleep/skip/weak assertion/native engine activation. Native wake readiness/physical erasure are exclusions, not acceptance gates for this fixture repair.

### #403 Character-only startup caller

Delivered: PR404 character caller/main/notice and concurrent app proof; PR410 pre-entry guard.

Original evidence coverage:

- Actual CharacterStore entered failure/reconciliation/fresh retry/stale/disposed, retained exact choice/verified=false, pending-before-notify and sync/async/reentrant cases: [character fixtures](../test/character_startup_test.dart), [caller](../lib/services/character_startup.dart).
- Same main helper and unchanged owner/persona/roster semantics: fixture source audit, [main](../lib/main.dart), [notice](../lib/ui/character_startup_notice.dart).
- Actual app concurrent character/appearance notices, Watch/Stop/back/body at compact/scaled EN/RTL light/dark: [visual fixture](../test/character_startup_visual_test.dart), [corrected 72-pixel evidence](evidence/issue403/README.md). PR404/410 full checks passed.

Unmet bounded criterion: none identified. Ready for manager disposition. Missing Hebrew glyphs in initial fixture font loading were corrected before committed evidence; see history below. Wider startup/native readiness and security bypass were excluded, not delivered or required here.

### #405 Language-only startup caller and shared RTL retry

Delivered: PR406 caller/main/independent notice, actual language observer and route-preserving EN-to-Hebrew retry; PR410 pre-entry guard.

Original acceptance coverage:

- Actual LanguagePreferences first/second-read failures, retained UI/speech choices, reconciliation/fresh retry/latest/disposed, sync/async/reentrant and caller-success versus owner state: [language fixtures](../test/language_startup_test.dart), [caller](../lib/services/language_startup.dart).
- Same main helper/load order, app replacement/disposal and no skipped security loads: source audit and [main](../lib/main.dart).
- Three concurrent independent notices with Watch at 320/390, 1/1.5/2, EN/Hebrew RTL, light/dark; each retry/back/Stop/body stays operable; language-only recovery and actual shared EN-to-Hebrew/speech retry updates RTL without route replacement: [visual fixture](../test/language_startup_visual_test.dart), [72-pixel evidence](evidence/issue405/README.md).
- Focused/full checks, analyze/format/diff reported and required CI verified: PR406/410 ledger. Fixture interruption history remains below.

Unmet bounded criterion: none identified. Ready for manager disposition. Storage owner, locale resolution, speech/restart policy and global theme remain unchanged. Other startup/native/biometric readiness is not a language-caller acceptance gate.

### #407 Host caller entered completion and notifier disposal

Delivered: PR408 pending-before-notify identical completion, pre-entry guard and deferred idempotent notifier disposal.

Original acceptance coverage:

- Actual BrainHostState held load/refusal with success/error: [host fixtures](../test/host_reload_controller_test.dart) assert work/retry/reentrant future identity, unsettled before release, one load and coherent final failure/loading state.
- Loading listener retry/fresh latest; disposal during loading/success/failure, repeated dispose and post-disposal no-op; no obsolete dependency entry/late publication: same fixture and [caller source](../lib/services/host_reload_controller.dart). Exactly-once notifier disposal is supported by `_notifierDisposed` guard and repeated/reentrant fixture assertions, not an instrumented native cleanup counter.
- Actual retained host failures/source audit of five main calls and both notice placements remain: same fixture; [historical unchanged notice proof](evidence/issue381/README.md), [notice test](../test/host_reload_notice_test.dart). PR408 full required checks passed.

Unmet bounded caller criterion: none identified. Ready for manager disposition. No main/UI edits; no new pixels needed. Native/MacHome/remote-provider fail-closed proof and retained-provider policy are explicit exclusions, not added gates.

### #409 Startup caller pre-notification lifecycle/current guards

Delivered: PR410 one guard each in appearance/character/language _run plus direct tests.

Original acceptance coverage:

- Reload then immediate synchronous disposal: zero loading mutation/notification/read; returned futures resolve; repeated dispose/post-disposal retries do not enter.
- Two synchronously queued reloads: obsolete work does not notify/read; latest alone enters and installed retry is identical/unsettled before release; all pending futures settle.
- Actual injected ThemeController/CharacterStore/LanguagePreferences held-read success/error and disposal after entry preserve retained owner state and character uncertainty: [appearance](../test/appearance_startup_test.dart), [character](../test/character_startup_test.dart), [language](../test/language_startup_test.dart) fixtures.
- Existing reentrant/sync/async/current source wiring and app/notice regressions: PR410 required checks. [Appearance](../lib/services/appearance_startup.dart), [character](../lib/services/character_startup.dart), [language](../lib/services/language_startup.dart) source guard before any loading publication.

Unmet bounded criterion: none identified. Ready for manager disposition. No UI/pixel/storage/main edits. Entered owner work may finish after disposal by explicit scope; no storage cancellation or whole-startup/native-readiness claim.

## Conflicts and historical limits

- **PR400 local test count:** PR prose says 1556, while its listed batches are 595 + 562 + 388 + 23 = **1568**. Reconciliation checked those existing log endings locally; no raw logs are published here. Treat 1556 as a reporting mismatch, not a verified total. Grouped wake start-failure timing errors occurred; the isolated 23 pass did not erase them. PR402 repaired the test observation and its first full exact-head CI succeeded.
- **Historical evidence:** issue391 README's capture defect is pre-PR394; issue397 README/PNG's invisible Stop/covered AppBar is pre-PR400. Do not silently rewrite evidence or schedule duplicate fixes. PR410 supplies later queued/disposed startup guards.
- **PR404 visual history:** initial Hebrew glyph omission was fixture-only and corrected before the committed evidence. **PR406 history:** two local attempts interrupted after a fixture theme-access fake-clock hang; final fixture initializes actual IO via runAsync. The committed README records this and final successful checks are separate evidence.
- **Visual review level:** prior workers reported full inspection of all committed captures. This reconciliation re-opened selected complete Settings, key uncertainty, hold caller failure, historical appearance RTL and current compact 2x RTL Watch/character/language samples, not every capture. Current RTL samples show readable notices/Stop/back/body; historical appearance sample confirms the old defect. No synthetic label authenticates a biometric route or real native session.
- **Scope holds:** #351 image/consent policy, #266 and #344 remain outside this reconciliation. No policy decisions, recurring/paid runs, native requests or unpublished shpalac work are transferred by this page.

## Keeping the map current

After another related merge, compare the original criterion against current source and exact-head evidence, add its delivery to the ledger, and revise only the affected unmet criterion/disposition. Keep historical failures and proof limits attached to their claims. Manager decides issue disposition; a ready row does not authorize issue closure/status/assignee edits.
