# #445 tray publication caller evidence

Bounded caller work on main `22296cf`, not a native tray-readiness claim.

## Contract and observations

Repository-wide publication search finds only MacHome's icon/title/menu calls.
The same tray_manager 0.2.4 singleton and original menu actions are retained;
MacHome owns its caller/listener lifetime only and never destroys the singleton.
Watch listeners request publication, never start/stop/change watch policy.

A joined completion is installed before queued entry and notifier callbacks.
Each request runs at most one entered pass and one fresh-state successor.
Each next operation samples actual watch state. Successful icon/title/menu
markers remain separate from desired state. Failed title/menu work remains
uncompleted even if desired state returns to an earlier successful marker.
Ordinary same-active ticks after failure do not write or erase the error;
explicit Retry tray or a new active transition can attempt fresh state.
Later notifications can request another bounded pass after completion.

Actual locked-plugin macOS asset and MethodChannel fixtures cover held/failing
icon/title/menu, actual ScreenWatch consent/local-only controlled clock/ticks,
reentrant join/disposal, startup vs active/stop bursts, exact counts/order,
prior-successful markers after failed transitions, explicit recovery and a
burst during the successor (no third pass). A held entered setIcon may finish
its internal asset-to-channel step after caller disposal. No later caller
operation or display is allowed; no native cancellation claim is made.

Actual failed setContextMenu replaces the plugin's Dart menu mapping before
native return: prior ids stop mapping while proposed ids map in the callback
fixture. That does not establish whether the native menu exists or is usable.

## Pixels and composition

32 composed cases use the actual caller and tray channel failure/retry flow:
normal/onboarding, EN/Hebrew RTL, 320/1000, 1x/2x, light/dark. Error, held
pending, repeat failure and success are exercised, with independent body,
window-action error and other existing notices/controls. All 16 contact sheets
were inspected directly, plus the three full-size originals committed here.
Tray copy/retry is readable, pending disabled, and success removes only the
tray notice. Existing compact/onboarding 2x body truncation and scroll viewport
clipping are visible; not repaired in this caller slice. Captures use scrolling
to expose action areas. This is mounted notice/composition evidence, not a
mounted MacHome/native-window test. MacHome wiring is separately source-tested
for exactly one notice per each of its two regions and disposal ordering.
Hidden-window recovery is not guaranteed. In-app watch Stop and OS reopen paths
are retained; no automatic Show, kill, watch or settings action was added.

## Transparent attempts

- Initial analyzer found five style infos; initializing formals/import fixed.
- Initial direct 23 + existing vision 11 and composed 32 passed.
- First combined full-test shell call hit its 120-second outer limit. Its
  running second batch finished normally; remaining batches ran separately.
  All 142 files passed across 427/558/615/456 tests, one existing skip.
- Final code audit found successor-loop capacity and the prior-marker return
  needed explicit bounds/uncompleted flags. Added two regressions. One older
  test incorrectly expected success while menu channel still failed after a
  return to the prior active state. Its expectations were strengthened to
  require a new menu attempt, preserve failure and use explicit successful
  retry. No assertion was removed or skip added.
- Final MacHome diff exposed two notices in onboarding rather than one in
  each region. Wiring repaired and source assertions strengthened per-region.
- Final full regression, analyzer and format results below are current-tree
  verification; remote required exact-head CI remains authoritative for merge.

## Boundaries

No plugin/native/singleton destruction, watch/driver/safety, speech/player,
phone/core/Settings/tutorial or other-owner edits. No hardware, paid run,
secrets, permission or #160 work. Refs-only; manager owns issue disposition.

Final tree: all142 test files passed, 427 + 558 + 615 + 458 = 2058 passed,
one existing skip. Final analyzer clean. All5 changed Dart files format clean.
Logs are retained alongside the screenshots, including the intermediate failed
expectation and repaired direct/composed57 pass run. Final full batch3 includes
both new bounded-successor and prior-marker regressions, as well as strengthened
per-region source assertions.
