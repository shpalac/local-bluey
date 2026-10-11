# Mac tray remainder

Historical snapshot: main `8db5818cf990a82782d66174a1a36aa4ddced709`, 11 October 2026. Read-only #435 audit. Only this document changes. No tray failure was reproduced, no new test or native run was made, and no implementation is selected. Delivered [startup caller status](MAC_STARTUP_REMAINDER.md) and [acceptance map](ACCEPTANCE_MAP.md) remain separate.

## Delivered publication status: 11 October 2026

Current main `982bdf986bc89a1c7a931deb91faa22514791f90`; docs-only #451 addendum. [PR446](https://github.com/shpalac/local-bluey/pull/446) delivered the separately selected #445 publication caller/UI. The435 historical audit and443 dated action status below remain unchanged; their publication containment suggestions are historical, not duplicate backlog. [Canonical current criteria](ACCEPTANCE_MAP.md#445-tray-publication-caller) records exact approved head/merge/head-matching required+docs checks, actual source/channel/asset/watch fixtures and reopened pixels.

Same tray singleton/menu actions, MacHome caller/listener lifetime only. [Caller](../lib/services/tray_publication_caller.dart) serializes startup/watch icon/title/menu, installs joined completion before queued entry/notification, re-samples actual watch state before each next operation and uses one latest-state latch per entered pass. Genuine successor-time notifications can drain a next sequential fresh pass; no hard-two-pass drop, snapshot queue or self-enqueue. Successful markers are separate from desired/uncompleted failure; same-active failure ticks do not write/clear it, explicit Retry tray/new active transition attempts fresh state. Successful countdown avoids menu churn. [Notice](../lib/ui/tray_publication_notice.dart) is independent/localized in both regions, pending disabled, local success hides only it.

Queued disposal prevents entry; entered plugin internals may finish (setIcon asset then channel), but no later caller operation/display. Failed setContextMenu updates plugin Dart mapping before native return; actual proposed/prior-id fixture does not prove native absence/reachability. No singleton destroy/recreation or native/plugin/watch/safety change. Hidden in-app recovery is not guaranteed. In-app watch Stop/OS reopen and Stop/Resume/Quit meanings retained.

**Still unselected:** process-wide singleton ownership/destroy/recovery and native lifetime/reachability; ordinary input permission/end/lifetime/shared-key overlap and phone-send candidates in the [separate audit](ORDINARY_HOLD_REMAINDER.md). PR448 is audit only; PR450 verifies unchanged requesting default and corrects comments, not consent/permission behavior or ordinary activation. Terminal/mute/window delivered action status remains below. No automatic Show/watch/kill/resume/mute/settings/retry, overlap winner or phone timing decision. Original91/212 remain CLOSED anchors. shpalac246/228/366/372/unpublished,393 native,351 consent/image and266/344 holds remain separate; no owner transfer/issue effects or hardware/paid/secrets/permissions/160 work.

## Delivered action status: 11 October 2026

Current main `4e50239a679484e7c65c309bd955f1eefb77af8f`; docs-only #443 addendum. The historical #435 audit below remains unchanged. Its terminal/mute/window suggestions and test proposals are now delivered by separately selected PR438/#437, PR440/#439 and PR442/#441, not duplicate backlog. [Canonical reconciliation](ACCEPTANCE_MAP.md#mac-explicit-actions-and-terminal-delivery) records original criteria, exact approved heads/merges/required and docs checks, current actual source/direct/composed fixtures and reopened pixels.

- [Terminal caller](../lib/services/speech_disposal_caller.dart): immediate same-order once-only retained owner disposal, installed joined completion, sync/async failure consumption, no retry/restart/UI/erasure guarantee.
- [Mute caller](../lib/services/speech_mute_caller.dart): immediate actual stop invalidation, joined local completion, original immediate phone broadcast per explicit event including duplicates/retry, localized independent pending/error notice both branches. No remote receipt/native playback/all-file erasure proof.
- [Window caller](../lib/services/window_action_caller.dart): icon/Show same show-before-focus path, no focus after failed show, Hide only, one entered intent plus bounded latest explicit successor, generic final-intent explicit retry. Caller-level disposal fences later focus/successors/display; unchanged entered plugin isMinimized/restore/show may finish. No native cancellation/visibility/focus or hidden in-app recovery guarantee.

**Still unselected:** setup/watch title/menu publication, desired-versus-published state, generic recovery surface and process-wide tray singleton/listener/destroy ownership. Current main still starts setup without consuming its future and supplies async watch publication to a void notifier listener. Existing source-derived overlap/menu-marker/post-dispose risks below remain unproven OS failures. Manager selects and coordinates any publication slice; no automatic watch/kill/resume/mute/settings action, owner change or whole-tray/native gate follows here. Stop/Resume/Quit meanings unchanged; original #91/#212 remain CLOSED anchors. Startup/onboarding/tutorial/recordGranted/clearBaseline/deletion boundaries remain separate. #351/#266/#344 holds, #246 shpalac/unpublished ownership and #393 native condition unchanged. Refs-only, no issue effects or ownership transfer.

## Historical #435 audit (unchanged below)

## Original expectations and current delivery

Original [#91](https://github.com/shpalac/local-bluey/issues/91) expects tray quick actions to use the same request path as face entry, with safety/logging and README platform limits. [#212](https://github.com/shpalac/local-bluey/issues/212) expects opt-in/off-by-default local-only watching, exclusions, visible countdown/one-tap Stop and cancellation within one second. Both issues are CLOSED in the current live issue read; this audit does not reopen or change their disposition. Their broad criteria are anchors, not permission to rewrite all OS entry points.

[README](../README.md) documents Ask Bluey (wake), Mute replies, Status, Show/Hide/Stop/Resume/Quit. [Main](../lib/main.dart) registers the tray listener and starts `_setupTray` in initState. Ask changes awake state and broadcasts wake; status shows current awake/kill text. Stop Bluey calls the existing SafetyGate kill and hold-key reset; Resume calls its existing reset and cleanup guard refresh; Quit exits. These synchronous action meanings remain unchanged. Ask is wake, not direct capture or a new request bypass. No safety, phone or native rewrite is proposed.

Main also registers `_syncWatchTray` on ScreenWatch, publishing a countdown title every notification and changing the menu when active state changes. [WatchBanner](../lib/ui/watch_banner.dart) supplies a separate localized in-app indicator/Stop above route content via the app builder. In-app availability when the window is hidden is not proven by this source.

### Delivered owner containment is not tray readiness

[ScreenWatch](../lib/services/screen_watch.dart) starts off, requires explicit session consent/local-only/allowlist, stops synchronously by changing active state/generation, canceling its ticker and firing registered cancellation callbacks before notifying listeners. [WatchDriver](../lib/services/watch_driver.dart) registers its stop hook, cancels its timer, clears pipeline/differ state and fences old ticks; entered old work drains before any restarted tick. [WatchPipeline](../lib/services/watch_pipeline.dart) and [WatchVision](../lib/services/watch_vision.dart) retain their gate/stale-result protections. These are Dart owner semantics, not proof that an entered native capture was physically canceled by a tray click. An ignored tray-update failure is not proof Stop cannot cancel work.

[SpeechService](../lib/services/speech.dart) invalidates startup generations synchronously and orders player work. Stop releases its listener/owned file in finally even when playback stop rejects; the returned operation still rejects, while the internal ordered tail consumes error to allow later work. Disposal is terminal/shared and attempts stop/release/player disposal. Clip deletion remains best-effort with cleanupProblem, not erasure proof. Tray mute does not need a second speech owner or retrying player implementation.

[SafetyGate](../lib/services/safety_gate.dart) changes killed/generation synchronously; kill listener errors are isolated and counted, with reentrant dispatch guarded. The current tray Stop Bluey action is not the same action as ScreenWatch.stop. This audit does not broaden either kill policy or assert that one implies the other.

## Exact remaining caller paths

### Setup and watch publication

Main `_setupTray` awaits setIcon then setContextMenu, but initState ignores its future. Icon/menu rejection can escape without UI status, retry or success receipt. `_syncWatchTray` is an async callback supplied to a void ChangeNotifier listener; ChangeNotifier cannot await that completion. Title rejection therefore escapes asynchronously and prevents that invocation from reaching the active-menu comparison.

After a successful title call, `_syncWatchTray` re-reads watch.isActive, assigns `_trayWatchActive` before awaiting `_setupTray`. If setup rejects, the local marker already says this state was handled. Subsequent notifications with the same active state will not retry the menu. No explicit setup retry exists. This is a precise source path, not reproduced plugin failure or proof the visible Stop item was absent.

Multiple notifications can enter title calls concurrently; startup setup and active-transition setups can overlap. Title text is captured before an await; menu content is sampled later after setIcon. No application queue, latest-generation check, installed completion or bounded successor separates those chains. A held older title can settle after a stop update, or an entered menu publication can outlive a later transition. This is an untested dependency-interleaving risk; it does not establish reverse completion on real macOS. Re-reading watch.isActive after title protects that local comparison from a captured old active boolean, but does not revoke already-entered title/menu effects.

Dispose removes tray/watch listeners but does not cancel already-entered futures; a held setIcon can resume into setContextMenu after teardown. No mounted/lifetime guard prevents that next entry. There is no trayManager.destroy in MacHome disposal. Destroying a process-wide tray requires explicit ownership selection; adding it by default could affect another listener/window.

Locked [tray_manager dependency](../pubspec.lock) is 0.2.4. Its inspected Dart implementation: setIcon may await asset loading on macOS then invokes MethodChannel; setTitle invokes MethodChannel; setContextMenu assigns its shared `_menu` before awaiting native publication. Thus a rejected publication can leave Dart event lookup using a proposed menu while native publication remains unverified. Menu event mapping/order after that failure needs a controlled plugin callback test before claiming a specific missing/wrong action. removeListener changes listener registration only, not pending calls. No dependency/native change is selected.

### Explicit window Show/Hide

Main icon click and Show call windowManager.show() and focus() independently, ignore both futures, and have no mounted guard or pending/error status. Hide ignores its future too. Locked [window_manager dependency](../pubspec.lock) is 0.5.2; its show awaits isMinimized, possibly restore, then native show, while focus independently invokes its channel. Focus can therefore enter before show completes at the Dart edge. Failure or rapid show/hide overlap has no app-level ordering/error policy. Real OS focus failure or wrong final window state is unproven. Successful window initialization in main is awaited before runApp and does not consume later action errors.

### Explicit Mute and terminal disposal

Tray Mute calls unawaited(_speech.stop()) then immediately broadcasts stopSpeech to phones. Local stop failure is unconsumed at the UI edge even though speech owner cleanup/order is tested. No truthful local pending/error presentation exists. The broadcast does not prove local mute completion or remote receipt. Preserve existing local/phone intent and don't silently change broadcast timing while adding caller containment.

MacHome also ignores `_speech.dispose()` during synchronous dispose. Existing owner terminal guards do not make its rejecting returned future harmless. A terminal error-reporting boundary may be a separate small caller slice; no retry/player restart after teardown should be introduced. Other key/phone teardown futures are separate delivered or unselected work, not bundled into a tray audit.

## Smallest independent options, not selected work

- Tray publication caller: inject existing tray operations, install a shared pending completion before entry, serialize entered writes with a bounded fresh-state successor, and record desired versus successfully published state separately. Lifetime guards can prevent queued/next writes after disposal, but cannot undo an entered native call. Generic error plus explicit refresh/retry can preserve safety without automatic watch/kill/resume/settings actions. Decide tray singleton ownership and recovery surface before implementation.
- Window action caller: explicit Show path awaits show before focus; catch a generic failure, guard lifetime and coalesce repeated identical actions. Choose ordering for conflicting Show/Hide and where an error is visible if the window could not be shown. A hidden in-app snackbar alone may not reach the user. No automatic Show or focus retry.
- Mute action caller: retain the actual SpeechService.stop and existing phone broadcast; consume its completion, show truthful local pending/failure and offer only explicit retry. Decide whether duplicate mute requests share one completion and keep broadcast semantics explicit. Terminal speech disposal error consumption is separate and never retryable after disposal.

No option changes speech/watch/capture/safety/native/plugin core, Settings/onboarding/tutorial ownership or phone delivery protocol. #351/#266/#344 holds, #246 shpalac acceptance and #393 owner-only native condition remain unchanged. Stop/Resume/Quit meanings are preserved. No implementation ownership transfers here.

## Proposed actual-caller test matrix

No tests below were added or run as tray fixtures in this audit.

1. Controlled actual tray MethodChannel/asset boundary: held/failed setIcon, setTitle and setContextMenu; startup versus active/stop/tick transitions; old entered title/menu then newer state; repeated notifications coalesce; failure cannot count as published state; explicit retry re-samples current state. Verify actual plugin menu event mapping with failed proposed-menu publication, not a hand-written fake assumption.
2. Queued disposal prevents entry; entered title/icon completion cannot start another publication after teardown; cancellation/result promises distinguish Dart display/lifetime fencing from native entered-call cancellation. Test reentrant state changes during notification. Verify singleton listener/destroy authority separately.
3. Actual window-manager channel path: held isMinimized/restore/show then focus, each sync/async failure; double Show and conflicting Show/Hide; queued/entered disposal; no raw error detail/automatic retry. Native visual/window state still requires separately authorized owner evidence.
4. Actual SpeechService with controlled playback/storage: held/failed local stop, duplicates, explicit retry, pending old play/stop/dispose; preserve current broadcast scope/order and don't infer remote mute receipt. Terminal rejected dispose is consumed without restart or disposed updates.
5. Regression existing ScreenWatch/driver/pipeline/vision, speech playback and safety fixtures. If a visible status/retry is selected, actual composed EN/Hebrew RTL compact/regular pixels and explicit actions with body/other notices must be inspected. No mounted Mac/native gate is invented for a bounded caller slice.

## Evidence checked and limits

Existing nine-file regression run passed 94 tests: [session](../test/screen_watch_test.dart), [consent](../test/screen_watch_consent_test.dart), [driver](../test/watch_driver_test.dart), [driver lifecycle](../test/watch_driver_lifecycle_test.dart), [pipeline](../test/watch_pipeline_test.dart), [pipeline lifecycle](../test/watch_pipeline_lifecycle_test.dart), [vision](../test/watch_vision_test.dart), [speech playback](../test/speech_playback_test.dart), [safety](../test/safety_gate_test.dart). Controlled owner tests cover off/excluded/no-call, synchronous stop hooks/stale results, held/error tick stop/restart without overlap, cleanup on stop/dispose rejection, and current provider failure. Main vision wiring is a source assertion, not mounted MacHome/tray integration. Repository tray keyword search found no direct main-tray/window action fixture, only a vision source-boundary delimiter reference; that is a search finding, not proof no test could exercise it indirectly.

Live GitHub contents read verified exact main/source revision:
- [Main source snapshot](https://github.com/shpalac/local-bluey/blob/8db5818cf990a82782d66174a1a36aa4ddced709/lib/main.dart)
- [ScreenWatch snapshot](https://github.com/shpalac/local-bluey/blob/8db5818cf990a82782d66174a1a36aa4ddced709/lib/services/screen_watch.dart)
- [Speech snapshot](https://github.com/shpalac/local-bluey/blob/8db5818cf990a82782d66174a1a36aa4ddced709/lib/services/speech.dart)

Dependency implementation inspected from cached exact locked packages; its source was read, not executed on macOS. All local link targets checked; document preview/current PR CI are separate delivery checks. One initial combined source read exceeded inline output budget, so task-driving main/watch/speech/plugin ranges and design guidance were re-read in bounded calls. A guessed speech_lifecycle_test.dart path did not exist; actual speech_playback_test.dart was found and read/run instead. No failed native experiment, new fixture, device/paid/recurring test or tray pixel claim. Source-derived risks remain unproven OS failures.

## Decisions before implementation

Select a bounded publication/window/mute caller slice and its recovery surface, clarify singleton lifetime ownership and conflicting-action ordering, and coordinate any owner changes with manager/shpalac. Do not use Ready recommendations or this audit to close/reassign issues. Docs-only findings are complete at this snapshot; native reachability/cancellation and whole tray readiness are not claimed.
