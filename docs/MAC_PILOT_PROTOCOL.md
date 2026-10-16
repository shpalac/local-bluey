# BLU-022: macOS opt-in pilot protocol

Status: **protocol proposed; pilot not yet conducted**. Issue: #578. Dependencies: BLU-011 and BLU-020.

## Scope and consent
- Limit pilot to named macOS app(s), named tester(s), and an agreed start/end window. Default OFF.
- Before enabling, show purpose, observed app/window scope, data categories, retention duration, and how to stop and erase data. Record affirmative consent and protocol version. Never infer consent from installation.
- Revoke consent immediately stops capture and suggestions; verify retained data is deleted according to the application's retention contract. No background resumption after restart without valid consent.
- Exclude password managers, banking, private/incognito windows, authentication dialogs and other sensitive surfaces. Do not collect passwords, tokens, raw screenshots or clipboard contents as pilot evidence.
- No automatic actions. Suggestions require an explicit human decision and must pass existing SafetyGate/approval controls. Denied macOS permissions must not trigger bypass or downgrade.
- Operate locally unless a separately documented, consented network operation is essential. Audit egress using OS/network instrumentation; never assume zero egress from absence of application logs.

## Preflight checklist (reviewer initials, date, evidence link)
- [ ] macOS version, app build SHA, test app allowlist and feature-flag defaults recorded
- [ ] BLU-011 privacy/data registry and BLU-020 stop/audit UX behavior reviewed against current main
- [ ] Accessibility/Screen Recording permission prompts and denial behavior manually verified
- [ ] Consent copy, keyboard/screen-reader navigation and RTL layout reviewed
- [ ] Local data location, encryption, retention and deletion behavior verified
- [ ] Network baseline and expected endpoints documented; unapproved egress = STOP
- [ ] Emergency stop, restart and rollback rehearsed
- [ ] Test owner and privacy/security reviewer sign below

## Test matrix
| Scenario | Expected behavior | Evidence |
| --- | --- | --- |
| Opt-in and normal suggestion | Only allowlisted app observed; suggestion visible; no automatic execution | Sanitized action/audit event |
| Invalid configuration or missing allowlist | Explicit validation error; no observation | Test result |
| Offline | Local behavior works or explicit unavailable state; no hidden fallback | Network trace |
| Operation timeout | Bounded wait, clear error and safe stop | Timed test |
| Permission denied/revoked | Explicit denied state; no capture or bypass | Manual macOS test |
| Cancellation/emergency stop | Stop observation and queued actions promptly | Audit timeline |
| App restart/crash | No silent restart of observation; persisted consent checked | Restart test |
| Retention expiry/deletion | Data removed per retention contract; no raw sensitive evidence | Sanitized inspection |
| RTL and accessibility | Controls navigable, labels announced, stop reversible | Manual checklist |

## Measurements and release gate
Record numerator and denominator, never only percentages:
- False suggestion rate = suggestions judged incorrect or inappropriate / reviewed suggestions. Review all suggestions in a small pilot; record disagreement and adjudication.
- Privacy incidents = unauthorized observations, egress events or retained sensitive records. **Any incident blocks expansion.**
- CPU: idle baseline and pilot p50/p95 process CPU percentage, sampled at a fixed interval on the same Mac and workload; record thermal/power conditions.
- Retained data: bytes and record count at start, end, after retention expiry, and after deletion; compare with documented retention contract.
- Stop latency and denied-permission/cancellation failures: record counts, worst observed latency and reproduction steps.

Pilot owner must define numeric performance and false-suggestion thresholds **before** collecting results. Do not claim pass without real macOS evidence, documented reviewer sign-off and an explicit go/no-go decision.

## Evidence and sign-off
Store only sanitized aggregate measurements, reproducible commands, test dates, build SHA, macOS version, and issue/PR links. Do not attach raw screenshots, user content, tokens or personal data.

| Role | Name | Date | Decision / evidence |
| --- | --- | --- | --- |
| Pilot owner | Pending | Pending | Pending |
| Privacy/security reviewer | Pending | Pending | Pending |
| macOS QA reviewer | Pending | Pending | Pending |

Decision: **NO-GO until signed**.

## Rollback
Disable the pilot feature flag, revoke macOS permissions, stop observation and pending actions, clear retained pilot data under the existing data deletion contract, and verify no background process or unexpected egress remains. Preserve only sanitized incident records. Re-enable only after remediation and fresh consent.

## CI boundary
Documentation validation may run on Ubuntu without hardware access. Real macOS TCC permissions, accessibility, CPU sampling and privacy/network verification are manual gates, not claims made by CI.

## Aggregate measurement helper (Refs #578)

`lib/benchmark/mac_pilot_metrics.dart` computes reproducible false-suggestion
rates and nearest-rank CPU p50/p95 statistics from numeric pilot aggregates.
A missing suggestion denominator or CPU data produces **unknown**, never
an artificial passing zero. Negative/non-finite readings and inconsistent
counts are rejected. CPU above 100% is permitted for multicore processes.
Any privacy incident or retained records after deletion are explicitly
flagged, but an incident-free summary is **not** evidence of zero egress.

This helper never captures screen content, performs network access, writes
files, or signs a pilot report. Run:
`flutter test test/benchmark/mac_pilot_metrics_test.dart`.
The signed real-Mac pilot, TCC, RTL and egress evidence remain mandatory.
