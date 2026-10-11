# ADR-001 amendment: brain reload failure and inbound deep links

Status: Owner decisions B/C, 2026-10-11. Parent ADR-001 is under review in PR #651; this amendment does not claim the parent PR merged or implementation complete.

## B. Brain reload failure: PAUSE

If settings cannot be verified after a failed reload, reject new brain/LLM requests until an explicit Retry succeeds with verified settings. Show a clear degraded state. Never fall back to the old provider. Test failed-reload rejection, successful Retry resumption and local-only no-send. Existing runtime consent, SafetyGate and entered-operation outcome/transport limits remain; no silent retry/replay.

## C. Inbound deep links: deferred

Keep the docs-only fix. Real inbound deep links are deferred to P3 and need their own security design first. Deep-link implementation issues remain blocked:owner until the owner unblocks them. This does not authorize native handlers, routing, side effects or new inbound input processing.

## Acceptance

These are architectural owner decisions, not shipped acceptance. Implementation, negative fixtures, exact-head CI and hardware evidence remain required. No code, provider, link handler, permission or persistence changes in this amendment.
