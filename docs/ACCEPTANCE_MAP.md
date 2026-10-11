# Refs-only acceptance map

Current snapshot: main `3ccb1d94c869dd115e5372993080d95f5746b443`, 11 October 2026. Current update: [#431](https://github.com/shpalac/local-bluey/issues/431), trust/permission rows only. Prior #423 snapshot at `93702642cb40b22a266845fa39a52a66d3d12b34` and its fifteen-row reconciliation are preserved below. Prior update scope: [#423](https://github.com/shpalac/local-bluey/issues/423). Original [#411](https://github.com/shpalac/local-bluey/issues/411) reconciliation at `975ad4e626c8fef85eba49f1399a23d8965ddeff` is preserved through its delivery ledger, unchanged rows and historical limits. The prior fifteen delivery issues were OPEN at the #423 check; new #427/#429 are OPEN at this #431 check. This page recommends dispositions; it does not close issues, change ownership, or decide policy.

## Reading the evidence

- **Ready for manager disposition** means no unmet original bounded criterion was identified from the current source, committed fixtures/evidence and successful exact-head checks. It is not a closure, native readiness claim, or proof that every app workflow works.
- **Deferred** names an original criterion that still lacks evidence. Non-goals, native exclusions and broader startup limits are not extra acceptance gates.
- Prior #423 evidence review (preserved): independently checked for that reconciliation: live issue bodies/comments, merged PR state/head/merge, required check results, current source and fixture assertions, repository evidence targets, and selected complete visual samples. Historical local test totals and full image-inspection claims remain worker reports unless explicitly verified below. Prior unchanged rows retain the original975ad4e source/fixture review; this update rechecked their live issue criteria/status and resolves all linked targets at current main, with fresh deep source review focused on391 and the staged deliveries. No new native/device run was performed.
- Current #431 review checks only affected #427/#429 live criteria, approvals, exact heads/merges/checks, current source/fixtures, six complete pixel originals and local link targets. Earlier rows and external link validation remain historical #423 evidence, not a fresh whole-map review.
- Source and test links resolve within the current snapshot; old ledger records remain historical. Evidence READMEs and PNGs are historical artifacts, not live-system proof. Preserve them; use the follow-up references below where they describe a defect since repaired.

## Disposition summary

| Issue | Proposed disposition | Exact remaining criterion | Next responsible owner |
| --- | --- | --- | --- |
| [#379](https://github.com/shpalac/local-bluey/issues/379) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#391](https://github.com/shpalac/local-bluey/issues/391) | Ready for manager disposition | None identified after PR416/418/420/422; explicit cleanup action now delivered. | Manager reviews original criterion disposition; Northbeam maintains this map. |
| [#393](https://github.com/shpalac/local-bluey/issues/393) | Deferred | Native recorder semantics remain unverified, explicitly required by original issue. | Owner-only native validation decision; no device/permission work authorized. |
| [#395](https://github.com/shpalac/local-bluey/issues/395) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#397](https://github.com/shpalac/local-bluey/issues/397) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#399](https://github.com/shpalac/local-bluey/issues/399) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#401](https://github.com/shpalac/local-bluey/issues/401) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#403](https://github.com/shpalac/local-bluey/issues/403) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#405](https://github.com/shpalac/local-bluey/issues/405) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#407](https://github.com/shpalac/local-bluey/issues/407) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#409](https://github.com/shpalac/local-bluey/issues/409) | Ready for manager disposition | None identified in bounded criteria; see limits below. | Manager reviews disposition; Northbeam maintains this map. |
| [#415](https://github.com/shpalac/local-bluey/issues/415) | Ready for manager disposition | None identified in bounded staged criteria; see coverage below. | Manager reviews disposition; Northbeam maintains this map. |
| [#417](https://github.com/shpalac/local-bluey/issues/417) | Ready for manager disposition | None identified in bounded staged criteria; see coverage below. | Manager reviews disposition; Northbeam maintains this map. |
| [#419](https://github.com/shpalac/local-bluey/issues/419) | Ready for manager disposition | None identified in bounded staged criteria; see coverage below. | Manager reviews disposition; Northbeam maintains this map. |
| [#421](https://github.com/shpalac/local-bluey/issues/421) | Ready for manager disposition | None identified in bounded staged criteria; see coverage below. | Manager reviews disposition; Northbeam maintains this map. |
| [#427](https://github.com/shpalac/local-bluey/issues/427) | Ready for manager disposition | None identified in bounded read-only trust caller criteria; no native/mounted-Mac gate added. | Manager reviews disposition; Northbeam maintains this map. |
| [#429](https://github.com/shpalac/local-bluey/issues/429) | Ready for manager disposition | None identified in bounded permission caller criteria; persistence/delete fencing explicitly excluded. | Manager reviews disposition; Northbeam maintains this map. |

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

### Later reviewed deliveries

PR414 remains a historical proposal, not implementation authority. PR416/418/420/422 are the separately assigned implementations. Their exact reviewed heads and merged results were rechecked live, along with head-matching required job results.

- [PR414](https://github.com/shpalac/local-bluey/pull/414)
  - Approved head: `13bc8369887d74c277654c663797309c52518fe1`
  - Main merge: `c934fd9cb512f9e8aa6a826814bad55e0dc8840c`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38090321005/job/114325253424) / [test](https://github.com/shpalac/local-bluey/actions/runs/38090321005/job/114325253354) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38090321005/job/114325253870) / [security](https://github.com/shpalac/local-bluey/actions/runs/38090321005/job/114325253299)
- [PR416](https://github.com/shpalac/local-bluey/pull/416)
  - Approved head: `405083fe735a1d31146cc2ed4d8ee791059320cb`
  - Main merge: `cb797a7008c925bfdcf67f30899a7969b272b308`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38091763237/job/114329451014) / [test](https://github.com/shpalac/local-bluey/actions/runs/38091763237/job/114329451211) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38091763237/job/114329451328) / [security](https://github.com/shpalac/local-bluey/actions/runs/38091763237/job/114329451210)
- [PR418](https://github.com/shpalac/local-bluey/pull/418)
  - Approved head: `5f754be311a045f4356771898ffcb8144814b260`
  - Main merge: `b8e376c9ad5ddc7ba6030b8e0e8b430dac8e6dc6`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38092838859/job/114332627039) / [test](https://github.com/shpalac/local-bluey/actions/runs/38092838859/job/114332627311) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38092838859/job/114332627212) / [security](https://github.com/shpalac/local-bluey/actions/runs/38092838859/job/114332627186)
- [PR420](https://github.com/shpalac/local-bluey/pull/420)
  - Approved head: `5125a96f48a53282ecd0057d3c4d77564aefbcd1`
  - Main merge: `e05821c576208ba42452589a0110f3a04c1a47e5`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38094961400/job/114338992533) / [test](https://github.com/shpalac/local-bluey/actions/runs/38094961400/job/114338992752) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38094961400/job/114338992621) / [security](https://github.com/shpalac/local-bluey/actions/runs/38094961400/job/114338992667)
- [PR422](https://github.com/shpalac/local-bluey/pull/422)
  - Approved head: `2b2d1661246b963536ae1a2cd93e13b2cad577b3`
  - Main merge: `93702642cb40b22a266845fa39a52a66d3d12b34`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38098700086/job/114349924326) / [test](https://github.com/shpalac/local-bluey/actions/runs/38098700086/job/114349924364) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38098700086/job/114349924476) / [security](https://github.com/shpalac/local-bluey/actions/runs/38098700086/job/114349924498)

### Trust and permission reviewed deliveries

- [PR428](https://github.com/shpalac/local-bluey/pull/428)
  - Approved head: `24e11a3211e66f0e54d7667d2902dbe7013f1746`
  - Main merge: `977fa888d76fcf6b08338e3133a0891feec9195e`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38102191747/job/114360233263) / [test](https://github.com/shpalac/local-bluey/actions/runs/38102191747/job/114360233307) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38102191747/job/114360233325) / [security](https://github.com/shpalac/local-bluey/actions/runs/38102191747/job/114360233242)
- [PR430](https://github.com/shpalac/local-bluey/pull/430)
  - Approved head: `82554f424ef6c9efeb8063aa67fbb2609a164b59`
  - Main merge: `3ccb1d94c869dd115e5372993080d95f5746b443`
  - Verified SUCCESS: [static](https://github.com/shpalac/local-bluey/actions/runs/38104324942/job/114366484205) / [test](https://github.com/shpalac/local-bluey/actions/runs/38104324942/job/114366484000) / [linux](https://github.com/shpalac/local-bluey/actions/runs/38104324942/job/114366484310) / [security](https://github.com/shpalac/local-bluey/actions/runs/38104324942/job/114366484263)

Live required check-run payloads matched each full head SHA; both PRs are MERGED. Manager approval in the corresponding issue Slack threads names these exact heads. No issue mutation follows from this ledger.

## Criterion reconciliation

### #379 Local-only preference ordering and Settings

Delivered: PR380 ordered read/write/clear ownership, safe uncertainty and actual Settings publication; PR382 contained the reported BrainHost caller gap; PR408 repaired that caller's retry completion.

Original acceptance coverage:

- False/throw toggle, retained state, explicit recovery and preserved unrelated edits: [actual Settings fixture](../test/privacy_clear_widget_test.dart), [Settings source](../lib/ui/settings_screen.dart).
- Entered read/write/remove versus registry clear, stale publication and fresh later choice: [ordering fixtures](../test/privacy_ordering_test.dart), [ordered owner](../lib/services/privacy_guard.dart), [registry entry](../lib/services/data_registry.dart).
- Read/remove failure retains honest state and propagates safe failure without fabricated OFF/rollback/erasure: the same owner/fixtures. STT/TTS/diagnostic fixtures assert zero HTTP effects on read uncertainty.
- Existing policy/regressions and full current-head checks: PR380 ledger; PR410 covers the original map snapshot; PR422 full test SUCCESS covers this current snapshot. [Failed](evidence/issue-379-local-only-failed.png), [cleared](evidence/issue-379-local-only-cleared.png), [recovered](evidence/issue-379-local-only-recovered.png) and [unverified](evidence/issue-379-local-only-unverified.png) Settings pixels are committed synthetic proof.

Unmet bounded criterion: none identified. Ready for manager disposition. The PR380 report's unobserved main BrainHost calls were subsequently contained by [host caller](../lib/services/host_reload_controller.dart) and [source-wiring fixtures](../test/host_reload_controller_test.dart), not left as new work. Retained remote-provider behavior after a failed privacy read is a separate policy limit, not solved by containment; no real-egress claim.

### #391 Key-only recording intent

Delivered: PR392 original permission/session/file owner and distinct key main wiring; PR394 underlying Dart capture uncertainty; PR396 separate hold-key caller observation. Later PR416/418 provide opt-in capture identity/cleanup/release, PR420 adopts them in the actual key owner with dedicated recovery, and PR422 exposes an independent guarded cleanup action in both Mac source branches.

Each original acceptance bullet was re-read from the live issue, not inferred from the later tasks:

1. **"Actual entered fake permission/start/stop vs key send/cancel/reset/dispose in both orders; late permission cannot open capture, entered start must be stopped/cleaned, stale result cannot send/process/update UI."** [Actual key fixtures](../test/key_recording_intent_test.dart) hold driver permission/start/stop versus send/cancel/dispose/fresh, assert no late start, exact current delivery and stale publication rejection. End-before-entry and reentrant pending cancel are separate fixtures. [Main source](../lib/main.dart) keeps reset routed through key cancel and distinct key send, with mounted guards after awaits. The main proof is source-only, as the original criterion permits.
2. **"Each session file delivered at most once to its own current send, cancellation deletes owned file; partial start/stop/delete failures generic and honest, no dropped cleanup ownership/physical erasure or native-stop guarantee."** The same fixtures plus [capture identity fixtures](../test/audio_capture_identity_test.dart) check exact files, one release claimant, cleanup-vs-release both orders, partial-open and failed-still-open retention, successful-current-driver null, held/failed deletion and file-only retry. [Key owner](../lib/services/key_recording_intent.dart) retains actual acquisition before await, never claims busy legacy capture, token-releases send and token-cleans cancellation. Externally transferred output is not deleted/redelivered; only a separately retained key File is deletable.
3. **"Overlapping key intents/fresh hold/stale errors and disposal contain futures/UI, explicit retry after failure, no silent callback retry. Preserve kill/resume generation expectations and report non-key capture overlap if broader arbitration is needed rather than changing face/phone flows."** PR420 actual explicit partial-start/failed-stop recovery fixtures retain failed retry then stop/delete without delivery, later fresh hold is separate. Capture-owned cleanup failure is stage-ambiguous, including capture-owned deletion, and requires dedicated `recover`; normal cancel/dispose cannot retry it. Separately key-owned transferred-file deletion remains explicitly cancel/dispose retryable. [Cleanup caller](../lib/services/key_cleanup_caller.dart) and [22 caller fixtures](../test/key_cleanup_caller_test.dart) retain failed/aborted explicit evidence only while actual cleanupPending, reject normal live acquisition, join pending stop/delete completion, and suppress stale/disposed publication. Optional `recover(canEnter:)` checks queued lifetime/allowed/generation before cleanup; default direct-owner retained cleanup under kill and entered cleanup completion remain unchanged. Tray resume now resets then refreshes guard only, never auto-retries. Shared face/key winner policy and cancellation of already-entered processing remain excluded and reported, not solved or made new acceptance gates.
4. **"Actual shared owner with injected AudioCapture/RecorderDriver fixtures plus source-reviewed key main wiring; clearly label helper/source-only vs mounted MacHome/device proof. Existing audio capture/hold-key/controller/lifecycle/request/phone/full tests, analyze/format/diff and four required current-head checks. Complete readable failure/pending/recovery pixels if main rendered text/state changes."** Current 53 direct key, 34 capture-identity, 22 caller and [33 notice fixtures](../test/key_cleanup_notice_test.dart) use actual owners/shared capture/injected driver, exact synthetic files and actual notice taps. [Current evidence](evidence/issue421/README.md) has 320/1000, 1x/2x text scale, EN/Hebrew RTL light/dark error, failed retry, pending, success and successive scrolling with actual FaceScreen/OnboardingScreen. Settings/close and permission effects are synthetic. Main wiring is source-reviewed, not mounted MacHome/device proof. PR422 exact-head full `test`, `static`, `linux`, `security` independently succeeded; analyze/format/diff and 1781 local passes/one skip are reported in the evidence guide, not an independently rerun local claim here.

Unmet original bounded criterion: none identified at current snapshot. **Ready for manager disposition**, not automatic closure. The earlier map's partial "explicit retry after failure" finding was accurate at975ad4e; PR420 supplied API-only recovery and PR422 supplied the actual UI action. No new native/mounted-Mac acceptance gate was introduced. Dart terminal receipts establish resource accounting only, not native microphone readiness, physical erasure or restart success. #393's original native condition remains separately deferred.

Historical [issue391 evidence](evidence/issue391/README.md) describes pre-394 capture defects and lacks the later action. Preserve it; the current identity/key/caller tests and issue421 pixels supersede its unresolved-recovery description, not its historical provenance.

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
- Full banner/app/watch/appearance regressions: PR400 required checks and PR410 historical and PR422 current-snapshot test SUCCESS. Local historical timing failures/count conflict are recorded below, not erased by later success.

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

## Staged key recovery delivery coverage

### #415 Identity-backed acquisition and no-delivery cleanup

PR416 delivered an opaque instance-bound attempted acquisition retained before temp/driver awaits, busy legacy returns no identity, atomic cleanup fence and same completion through stop/deletion. Positive no-entry/cleaned/transferred receipts are distinct from mismatch/disposal uncertainty. Transfer reports external ownership; it is not alone permission to delete output or promise key reuse. [Capture source](../lib/services/audio_capture.dart) keeps evidence on bounded handles, no unbounded registry. [Actual identity tests](../test/audio_capture_identity_test.dart) cover partial start, failed-still-open retry, current null, held/failed deletion and file-only retry, cap, busy legacy, external old/new zero effects, foreign identity/temp failure/disposal. Legacy signatures and cap behavior were preserved; later activation is separately PR420/422. No unmet staged bounded criterion identified. Ready for manager disposition; native condition remains #393.

### #417 Token release and exact resource ownership

PR418 delivered pre-await release fencing and at-most-one file claimant. Cleanup selected before consumption wins no-delivery in both tested orders; an already transferred File is not retroactively deleted. [Identity fixtures](../test/audio_capture_identity_test.dart) cover concurrent release, held-start/cap/null/error, cleanup/release ordering, external newer legacy zero effects/new release, foreign/no-entry/disposed, held deletion and closing. Terminal outcomes cannot target a newer candidate. No key/main/UI activation or overlap winner promise follows from this API-only stage. No unmet staged bounded criterion identified. Ready for manager disposition.

### #419 Actual key token adoption and explicit API

PR420 replaced generic key ownership/start/stop with acquire/release/cleanup identity, with busy legacy/no claim and explicit coalesced recover installed before notification. [Key fixtures](../test/key_recording_intent_test.dart) exercise actual capture/driver/exact files, old positive receipts, separately key-owned failed deletion, external-new zero effects, held stop/delete/cap, fresh/cancel/kill/dispose, and disposed uncertainty. Capture-owned stage-ambiguous failures require dedicated recovery; separate transferred key File remains cancel/dispose retryable. Fresh hold never hides recovery. This stage was API-only; caller activation came in PR422. No unmet staged bounded criterion identified. Ready for manager disposition.

### #421 Independent cleanup action and lifecycle/layout

PR422 wires [caller](../lib/services/key_cleanup_caller.dart), [localized notice](../lib/ui/key_cleanup_notice.dart) and [bounded shared notice region](../lib/ui/mac_notice_region.dart) only into source-reviewed MacHome lifecycle/both branches. Explicit retry sends/starts nothing. Current Dart cleanup receipt hides only outstanding key notice; failed retry stays generic and actionable. Caller pending completion precedes notify and joins actual stop/delete. Queued caller predicate prevents post-dispose/kill entry, entered work may finish; failed/aborted evidence survives suppressed pending owner publication only while cleanup remains and fresh acquisition invalidates it. Original scope said report core conflict before changes: two races were reported, then manager selected this narrow predicate/evidence exception before implementation; no new status enum/global arbitration.

[Caller tests](../test/key_cleanup_caller_test.dart) cover queued/entered kill/dispose, reentrant/notifier containment, safe retry/old external output/separate files, no automatic guard retry. [Notice tests](../test/key_cleanup_notice_test.dart) prove actual taps, failed/pending/success, killed disabled-to-resume enabled with no effects until tap. Main tray reset then refresh is source-asserted. [Evidence guide](evidence/issue421/README.md) and [compact EN light2x](evidence/issue421/421-320-2-en-light.png), [compact Hebrew dark2x](evidence/issue421/421-320-2-he-dark.png), [regular original](evidence/issue421/421-1000-2-en-light-normal-error-key-top.png) show successive scroll positions with existing independent notices/controls. The structural region caps at45% viewport, preserves existing wording/actions/visibility and body controls. Reconciliation re-opened these selected complete pixels; manager's broader inspection is recorded separately. Synthetic actual widgets/source-only main, not native or mounted MacHome. No unmet bounded criterion identified. Ready for manager disposition.

### #413 Historical proposal provenance

[KEY_CAPTURE_RETRY_CONTRACT.md](KEY_CAPTURE_RETRY_CONTRACT.md) remains the reviewed PR414 proposal at57c1220. Its private-session/generic-stop/no-recovery source facts and 16-case proposed matrix were true at that snapshot. They are historical, not current API descriptions or implementation authority. Separately assigned PR416/418/420/422 now implement the identity/cleanup/release/API/action slices. No host restart or driver recreation guarantee was selected. Keep proposal facts/alternatives unchanged; read the current map and source for delivered mechanics.

## Mac trust and permission delivery

### #427 Read-only Accessibility observation

Original selected criteria are in [live #427](https://github.com/shpalac/local-bluey/issues/427), not inferred from the historical audit. PR428 supplies the [actual trust caller](../lib/services/trust_observation.dart), [localized notice](../lib/ui/trust_observation_notice.dart) and [main](../lib/main.dart) routes.

- Actual production default is HostControl.forPlatform().isTrusted. Unknown/loading, current true/false and failed observation remain distinct. Historical lastObservation is not current grant proof during loading/error; even a previous true result still shows failed/unverified notice after a new error.
- Explicit checks join installed pending completion. Resume before entry joins queued work; during an entered read it requests one sequential fresh successor, bursts coalesce, superseded results/errors do not publish. The same future covers successors; further resumes during a successor can request another fresh read, with one latch and no concurrent probes/unbounded queue. No automatic retry after failure. Pending/lifetime guards precede notifications; queued/entered/reentrant disposal is contained.
- [17 actual caller/channel fixtures](../test/trust_observation_test.dart) cover actual MacHostControl/NativeControl MethodChannel true/false/null mapping, channel error, sync/async errors with retained prior values, held startup/resume bursts, successive fresh completion, duplicate/reentrant check, queued/entered/terminal disposal and source-only main startup/resume/dispose/both branches. Read/retry/resume sends only isTrusted, never askPermission or Settings.
- [32 composed notice cases](../test/trust_observation_notice_test.dart) cover unknown/error/denied/pending/recovered/failed-after-grant, disabled retry and explicit taps. Verified denial alone offers unchanged explicit askPermission then openAccessibilitySettings. Actual shared MacNoticeRegion, FaceScreen/OnboardingScreen, host/hold/key notices and recovery card are composed at320/1000,1x/2x, EN/Hebrew RTL, light/dark. [Evidence guide](evidence/issue427/README.md) records full-suite1830/one skip and final49/analyze/format/diff as historical worker execution, separate from independently verified head-matching CI.

Unmet original bounded criterion: none identified. Ready for manager disposition, not closure. Main proof is source-only; actual widgets and mocked channel are synthetic, not mounted MacHome/native permission/device proof. Settings callback's existing errors remain excluded, not newly contained. Watchdog/NativeControl/Swift permission policy and onboarding/tutorial owners were not changed. Original conditional refs-only/native exclusion is preserved, not converted into a new acceptance gate.

### #429 Retained permission-recovery observation

Original selected criteria are in [live #429](https://github.com/shpalac/local-bluey/issues/429). PR430 supplies [caller](../lib/services/permission_observation.dart), [notice](../lib/ui/permission_observation_notice.dart) and same retained watchdog/main routes.

- Actual default is the retained PermissionWatchdog.recheckRevoked. Unknown/loading/current/failed describes recovery observation, not grant readiness. Probe/store failure retains prior list with honest generic unverified status, never fabricated denial/grant/empty current. Explicit successful current read replaces only with actual result.
- Installed check join covers actual probes and baseline I/O. Fresh resume uses the same sequential latch/completion semantics as trust. Disposal fences queued source entry/late display, not already-entered watchdog writes. No automatic failure retry.
- [16 actual caller fixtures](../test/permission_observation_test.dart) use controlled PermissionChecker/preferences with actual watchdog: each checker failure, actual store read error, held baseline write completion, sync throw, retained error/fresh result, old failure/resume bursts, original clearBaseline and per-id display dismissal, already-produced delayed list filter, queued/entered/reentrant disposal and source assertions.
- Main captures selected permission at build; original explicit Fix/Later content and clearBaseline(selected id) effects remain. Caller dismissal only removes display and invalidates older entered list versions. Fresh post-dismiss revocation is still watchdog-controlled; no owner/persistence rewrite. Onboarding recordGranted is unchanged.
- [32 composed cases](../test/permission_observation_notice_test.dart) use actual caller/watchdog/notice plus independent failed trust, host/hold/key notices, FaceScreen/OnboardingScreen and normal recovery card. Retry/pending/current/retained failure, unchanged Fix/Later, other controls and scrolling are covered across the same compact/regular EN/RTL/scales/themes. [Evidence](evidence/issue429/README.md) records134-file1878/one skip, permission batch599 and final48/analyze/format/diff as prior execution, not a fresh local rerun claim in this map. Head-matching required CI independently succeeded.

Unmet original bounded criterion: none identified. Ready for manager disposition. **Caller display fencing is not deletion fencing:** entered watchdog baseline writes may outlive caller/disposal/delete-all. Main source-only and synthetic composed controls are not mounted Mac/native proof. Ignored recordGranted/clearBaseline futures, Settings reset and raw onboarding/tutorial reads are adjacent unselected boundaries, not silently claimed safe.

### Current startup boundary and visual provenance

[MAC_STARTUP_REMAINDER.md](MAC_STARTUP_REMAINDER.md) preserves historical #425 audit and adds current status: trust/permission suggestions are delivered, not duplicate backlog. Raw onboarding isDone.then and tutorial isDone.then still need manager/shpalac coordination; owner-run/replay/unknown-route choices remain unselected. No #223-227/#247 transfer or source/UI/new test work follows from this docs update.

Reconciliation directly reopened six complete originals: trust [compact EN denied action](evidence/issue427/320-2-en-light-normal-denied-action.png), [compact RTL pending](evidence/issue427/320-2-he-dark-onboard-pending.png), [regular RTL error](evidence/issue427/1000-2-he-dark-normal-error.png); permission [compact EN retained error](evidence/issue429/320-2-en-light-normal-retained-error.png), [compact RTL pending](evidence/issue429/320-2-he-dark-onboard-pending-retained.png), [regular RTL error](evidence/issue429/1000-2-he-dark-normal-error.png). New status text/actions readable with independent body and successive scrolling; not all controls shown at once. Existing compact2x onboarding heading/chip truncation remains unchanged; full prior16-sheet inspections and scroll-tap claims are recorded in guides, not newly repeated here. No native Hebrew-language review claimed.

Historical failures remain intact: PR428 normal-route16 failures used a wrong Dismiss selector, repaired to actual Later, then all32 pixel cases passed; test braces lint fixed before final49. PR430 initial32 expectation failures came from fixture grant-state inconsistency, actual watchdog correctly returned multiple revocations; controlled grants repaired without assertion weakening, all32 pixels and final48 passed. This reconciliation's unsuccessful guessed Slack thread lookup returned thread_not_found; recovered exact root timestamp from live channel and read correct thread, no send to wrong thread. Initial rendered map separated the new rows from the Markdown table with a blank line; repaired before final preview.

Retained remote-provider and hold-key policy, #351/#266/#344 holds, #246 shpalac acceptance and #393 native condition remain separate. Neither row claims permission grant, native recorder readiness, physical erasure, first answer, or post-delete baseline safety. No newly invented device/mounted-Mac gate or paid/recurring run.

## Conflicts and historical limits

- **PR400 local test count:** PR prose says 1556, while its listed batches are 595 + 562 + 388 + 23 = **1568**. Reconciliation checked those existing log endings locally; no raw logs are published here. Treat 1556 as a reporting mismatch, not a verified total. Grouped wake start-failure timing errors occurred; the isolated 23 pass did not erase them. PR402 repaired the test observation and its first full exact-head CI succeeded.
- **Historical evidence:** issue391 README's capture defect is pre-PR394; issue397 README/PNG's invisible Stop/covered AppBar is pre-PR400. Do not silently rewrite evidence or schedule duplicate fixes. PR410 supplies later queued/disposed startup guards.
- **PR404 visual history:** initial Hebrew glyph omission was fixture-only and corrected before the committed evidence. **PR406 history:** two local attempts interrupted after a fixture theme-access fake-clock hang; final fixture initializes actual IO via runAsync. The committed README records this and final successful checks are separate evidence.
- **Visual review level:** prior workers reported full inspection of all committed captures. The original975ad4e reconciliation re-opened selected complete Settings, key uncertainty, hold caller failure, historical appearance RTL and current compact 2x RTL Watch/character/language samples, not every capture. Current RTL samples show readable notices/Stop/back/body; historical appearance sample confirms the old defect. The current9370264 update additionally re-opened compact EN/light2x, Hebrew/dark2x and regular key-cleanup samples. No synthetic label authenticates a biometric route or real native session.
- **Scope holds:** #351 image/consent policy, #266 and #344 remain outside this reconciliation. No policy decisions, recurring/paid runs, native requests or unpublished shpalac work are transferred by this page.

## Keeping the map current

After another related merge, compare the original criterion against current source and exact-head evidence, add its delivery to the ledger, and revise only the affected unmet criterion/disposition. Keep historical failures and proof limits attached to their claims. Manager decides issue disposition; a ready row does not authorize issue closure/status/assignee edits.
