# Mac startup remainder

Snapshot: main d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d, 11 October 2026. Read-only audit for #425 of four MacHome startup callers. No source, fixture, UI, native or permission changes. Prior [acceptance map](ACCEPTANCE_MAP.md) remains delivered, with its limits. This is not a whole-startup readiness claim.

## Evidence and ownership

Main calls onboarding done-read, tutorial done-read, trust probe and permission recheck independently in initState; resume rechecks only permissions. [Main startup and disposal][main] are source-reviewed, not mounted MacHome or device evidence. Current injected-owner/widget fixtures were read and 80 unchanged tests passed locally: tutorial, tutorial gating/replay, onboarding checks/screen, permission watchdog/dismissal and conversation. No new failing fixture was written, so the remaining interleavings below are source reasoning, not reproduced failures.

[README][readme] anchors actual gestures, Accessibility-dependent pointing, live permission onboarding and first-run return after deletion. It does not explicitly describe the first-steps replay contract. That contract is in [tutorial owner][tutorial], [Settings replay][settings] and original #176/#226. [Onboarding][onboarding] preserves explicit setup-later and capability-aware summary; setup completion is not a live permission or first-answer result. Native permission checks are read-only preflights, not grants.

Live GitHub evidence: #223/#224/#225/#226/#227 and #247 remain OPEN and assigned shpalac. PR232/233/234/235/236/257 are MERGED. Their current source must be preserved; open parent issues are not an instruction to redo their implementations. #354/PR355 and #357/PR358 are CLOSED/MERGED narrow owner repairs. No shpalac-authored open PR was returned by the current query; that does not establish absence of unpublished/local work. Any implementation touching Settings, onboarding or tutorial handoff needs explicit manager ownership coordination first. No transfer is made here.

## Four caller paths

### Onboarding done-read

Entry: OnboardingScreen.isDone directly awaits SharedPreferences.getInstance and getBool('onboarding.done'). Absent flag means false; a thrown read is a failed read, not absence. Main starts with showOnboarding=false and chains then without a local error handler. On false it uses mounted before setState(true); true does nothing. Disposal prevents that setState, but does not consume read rejection or give startup current-operation ownership.

Remaining source-derived paths:
- getInstance or getBool throws: the derived startup future rejects, with no local catch/status/retry. Default false UI state remains, which must not be described as verified onboarding completion.
- A delayed false observation arrives after a mounted onboarding completion: the callback can re-open setup because it checks only mounted. Whether this can occur with the actual SharedPreferences singleton's timing needs a controlled read seam, not a claim that production snapshots arbitrary values.
- Delete-all explicitly sets showOnboarding=true in both Settings callbacks. A late true read cannot currently hide that because the callback has no true branch. A proposed symmetric true/false caller must preserve this property and invalidate the old read before publication. Do not invent a current hide-after-delete defect.

Already contained: [onboarding screen][onboarding] has per-check error state, step/refresh generations, duplicate verify guard and mounted/disposed checks for permission refresh. These do not cover the separate MacHome isDone chain. Existing [onboarding widget tests][onboardingtests] exercise slow verify/disposal/errors/unknown Local Network, not controlled MacHome done-read versus completion/delete.

Smallest candidate: a distinct startup read caller with safe read-failure status, current generation, lifetime guard and explicit retry. Keep persisted flag and first-success owners unchanged. Invalidate on completion/delete and retain the current first-run transition. Manager must select initial read-uncertainty presentation: showing setup versus retaining normal route with an independent notice. No unknown flag should be called completed, and neither choice grants permissions.

Proposed actual-owner matrix: done true/false/read throws; queued disposal before read entry; disposal after entry; held done-read versus completion/delete; older read success/error versus explicit newer retry; repeated retry joins pending completion. Inject the done-read dependency and use its real persistence method in a controlled preferences fixture, not a parallel fake implementation.

### Tutorial done-read

Entry: TutorialController.isDone separately reads SharedPreferences, outside the controller's ordered write/reset queue. Main then calls dismiss on true without mounted or run-generation check; false is a no-op, read failure has no caller handler.

Already contained: [tutorial owner][tutorial] fences and orders completion writes versus reset, coalesces terminal events and exposes safe storageError. Void completion events consume errors. [Replay fixtures][tutorialreplay] prove entered skip/point/answer writes versus reset, both success/error, repeated events and disposed owner safety. This audit's unchanged tests passed; do not duplicate #357.

Remaining source-derived paths:
- Startup true observation held while Settings starts a replay, then applied afterward: dismiss increments owner generation, clears completion/resetting and hides the run. If reset removal is already entered, its later completion is stale and cannot publish wake/visible. If removal is queued, the generation check can skip it. This bypasses the repaired completion-versus-reset contract because the raw read is not part of that contract.
- MacHome disposal while the read is entered does not prevent its callback mutating the still-live app-wide tutorial singleton. Removing MacHome's listener is not an owner-mutation fence.
- Done-read rejection is not consumed. A false read does not reset a previously hidden singleton, so a flag read alone is not proof of fresh-run state.

Smallest candidate: contain the startup read and apply dismiss only for the same live owner run. A MacHome-local generation alone cannot see reset from Settings unless that call site explicitly invalidates it; the owner's run generation is private. Manager must choose a narrow read-only owner observation/apply API versus a coordinated Settings replay invalidation hook. Do not copy a second tutorial state machine or change reset/flag-clear semantics. A failed read can have an independent safe retry notice without pretending completion was recovered.

Proposed matrix: held actual done-read true versus reset before entry, during entered removal and after reset; completion/skip while read pending; disposal of caller versus continued singleton use; stale error versus fresh retry; false result preserves current run; no old read dismisses or cancels newer replay. Existing storage-completer fixtures are reusable evidence, but do not already test this startup path.

Adjacent boundary, not an assigned implementation: Settings ignores reset's throwing future and immediately announces that the tutorial will show; TutorialCard passes skip directly to a void button. The owner has truthful failure state, but those UI call sites do not consume/display it. Report to the manager/shpalac rather than widening this four-caller task.

### Trust probe

Entry: [HostControl.forPlatform][host] returns MacHostControl on macOS; isTrusted delegates to [NativeControl][native]. The [Swift bridge][swift] returns AXIsProcessTrusted. The Dart channel defaults null to false but does not catch channel failures. Main awaits it and publishes trusted only while mounted. It starts trusted=false and displays an Accessibility-needed banner on false.

Already contained: no setState after disposal. Probe does not request permission. It is separate from the explicit banner action that asks permission and opens Settings.

Remaining source-derived paths: channel failure rejects the ignored startup future with no error status/retry. A failed observation remains indistinguishable in that banner from a verified false result. Only initState calls checkTrust: resume checks watchdog permissions but never refreshes this trusted flag. After granting Accessibility in Settings, the banner can remain stale even if watchdog records a new grant. No trust result currently controls permission authorization; this audit does not change tool/native policy.

Smallest candidate: read-only trust caller with current-result/lifetime guards, explicit safe failed/unknown status and retry, plus manager-selected resume refresh. Keep permission-request actions explicit and unchanged. If retries/resume are added, establish latest/coalesced observation rules before implementation.

Proposed matrix: actual injected HostControl returns true/false, synchronous throw or future error; held probe then dispose; older retry versus newer success/error; resume grant/revoke observation; no askPermission/open settings effects from startup/retry. [Host selection test][hosttest] covers type selection and unsupported platforms, not MacHome mounted errors or a real grant.

### Permission recheck

Entry: startup and each resumed event await watchdog.recheckRevoked, then set revoked while mounted. [Watchdog][watchdog] probes every permission sequentially before ordered baseline I/O. Live checker calls Accessibility, screen preflight, mic authorization and returns false for Local Network because no preflight exists. These calls do not prompt. A failed checker/store read rejects rather than becoming denied permission; the main caller does not consume it.

Already contained: [dismissal fixtures][dismissal] prove per-id observation invalidation and ordered removal prevent an entered probe restoring a dismissed baseline or returning that id as stale revoked. New post-dismiss observations can record a real grant. [Sequential watchdog tests][watchdogtests] preserve normal grant/revocation behavior. A caller change must not replace these owners or treat a failure as denial.

Remaining source-derived paths:
- A slow old check and a newer resume check can complete probes in reverse order. I/O is serialized in probe-completion order, not invocation order, and main has no latest-generation filter. An old result can overwrite a newer recovery list, unless that id's dismissal version changed. Existing dismissal ownership does not mean every newer recheck supersedes older observations.
- One rejected probe prevents that operation's remaining checks and baseline/result work. Caller keeps the previous list but has no honest failed/unverified status. Safe independent retry should preserve the retained list without claiming current grant knowledge.
- Disposal suppresses main publication but does not stop an entered watchdog check/baseline write. Delete-all removes watchdog keys through [registry][registry], independently of this watchdog's per-instance queue/versions; a pre-delete probe can write a granted baseline afterward. Caller-only latest-publication fencing cannot promise no post-delete persistence. This needs separate owner/manager deletion coordination, not a silent flag-clear redesign.

Smallest candidate: caller containment/current publication, retained recovery state, pending retry coalescing, safe status and disposal guard. Manager must decide whether resume joins an existing observation or requires a later fresh one. A latest caller can suppress stale display, but cannot make already-entered baseline I/O disappear. Preserve the owner's established new-grant behavior and no-prompt contract.

Proposed matrix: actual watchdog with controlled checker true/false/error in each permission; held earlier recheck versus later resume; retained list on error; retry join through probes and baseline writes; dismissal while caller pending; queued/entered disposal; delete boundary explicitly marked unproven unless separately assigned owner fencing is tested. Use no sleeps to establish entry.

Adjacent boundary: onboarding onDone ignores recordGranted's future, and recovery dismissal ignores clearBaseline's future. These may reject at the UI edge. They are not repaired or claimed safe by this audit; any task expanding to them needs manager scope and shpalac coordination.

## Do not add duplicate work

[Conversation owner][conversation] load catches unreadable/malformed retained data and reports historyProblem without overwriting unknown bytes. [Conversation fixtures][conversationtests] cover read failure, explicit recovery and entered read versus clear; they passed in this audit. Ignoring load's future in main does not by itself prove the same raw-read defect. No conversation repair is proposed.

Prior appearance/character/language/host/hold/key caller deliveries remain as recorded in the acceptance map. No new gate is attached to those rows. Existing #351/#266/#344 holds, shpalac #246 acceptance, owner-only #393 native condition and named-device first-success requirements are unchanged.

## Manager decisions before implementation

1. Confirm a bounded Mac startup read caller task and its route/unknown presentation; coordinate onboarding completion/delete invalidation with shpalac.
2. Select tutorial owner-run observation versus coordinated replay hook. Neither option is authorized by this audit.
3. Select trust resume refresh and permission resume/coalescing semantics. Keep permission grants explicit and retained baseline ownership separate from display.
4. Keep entered watchdog persistence versus delete-all as a separate ownership decision. A main-only patch must not claim deletion fencing it cannot provide.

Docs-only findings are complete at this snapshot. No native/device/model run, actual OS grants, permission prompt, real first answer or unpublished-work clearance is claimed.

## Verified issue and PR references

- [#223](https://github.com/shpalac/local-bluey/issues/223) OPEN, assigned shpalac.
- [#224](https://github.com/shpalac/local-bluey/issues/224) OPEN, assigned shpalac.
- [#225](https://github.com/shpalac/local-bluey/issues/225) OPEN, assigned shpalac.
- [#226](https://github.com/shpalac/local-bluey/issues/226) OPEN, assigned shpalac.
- [#227](https://github.com/shpalac/local-bluey/issues/227) OPEN, assigned shpalac.
- [#247](https://github.com/shpalac/local-bluey/issues/247) OPEN, assigned shpalac.
- [#354](https://github.com/shpalac/local-bluey/issues/354) CLOSED, assigned northbeamventures-cell.
- [#357](https://github.com/shpalac/local-bluey/issues/357) CLOSED, assigned northbeamventures-cell.
- [PR232](https://github.com/shpalac/local-bluey/pull/232) MERGED, merge `b84f0d152aa231ff2e94534d412a0774c317cb23`.
- [PR233](https://github.com/shpalac/local-bluey/pull/233) MERGED, merge `815e69b01e851db8b5cab4c1d63ba28bb080e773`.
- [PR234](https://github.com/shpalac/local-bluey/pull/234) MERGED, merge `d90b9f14046cb347cc85085f864ccace68e6cacb`.
- [PR235](https://github.com/shpalac/local-bluey/pull/235) MERGED, merge `7cacd250ed6f4a3aab828e93f7b3cee232fc0147`.
- [PR236](https://github.com/shpalac/local-bluey/pull/236) MERGED, merge `b50f46191399465c746f1663dfdc270ea5ca9691`.
- [PR257](https://github.com/shpalac/local-bluey/pull/257) MERGED, merge `ab214aa99021bd3cb53e787af80b779d71876442`.
- [PR355](https://github.com/shpalac/local-bluey/pull/355) MERGED, merge `5f851d99a03a7f130dcbedaf4bf15b404b413e9e`.
- [PR358](https://github.com/shpalac/local-bluey/pull/358) MERGED, merge `49419456a194b73d535dbffd1e06e86e6ec059bb`.

[main]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/lib/main.dart
[readme]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/README.md
[tutorial]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/lib/services/tutorial.dart
[settings]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/lib/ui/settings_screen.dart
[onboarding]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/lib/ui/onboarding_screen.dart
[onboardingtests]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/test/onboarding_test.dart
[tutorialreplay]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/test/tutorial_replay_test.dart
[host]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/lib/services/host_control.dart
[native]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/lib/services/native_control.dart
[swift]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/macos/Runner/NativeControlChannel.swift
[hosttest]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/test/host_control_test.dart
[watchdog]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/lib/services/permission_watchdog.dart
[dismissal]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/test/permission_dismissal_test.dart
[watchdogtests]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/test/permission_watchdog_test.dart
[registry]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/lib/services/data_registry.dart
[conversation]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/lib/services/conversation.dart
[conversationtests]: https://github.com/shpalac/local-bluey/blob/d9c1d3f6833960826ba5dbeb7d6ca229ab5ee84d/test/conversation_test.dart
