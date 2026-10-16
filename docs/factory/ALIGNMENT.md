# Local Bluey: Autonomous Software Factory alignment

This is an **adoption audit and active agent contract**, not a claim that an always-on factory is deployed. The portable source specification is [agent-team-kit factory v1 PR #45](https://github.com/shpalac/agent-team-kit/pull/45); see its `docs/factory/SPECIFICATION.md` and `docs/factory/ADOPTION.md`. This file records the local reality and planned migration. The target project adapter is [`.factory/config.yaml`](../../.factory/config.yaml).

## Capability map against the generic factory

| Capability | Existing local implementation | Status and next proof |
|---|---|---|
| Agent entry point | `.team/PROTOCOL.md`, `.team/roles/`, `.team/project.md`; root `AGENTS.md` is in pending [PR #892](https://github.com/shpalac/local-bluey/pull/892) | **Pending.** Do not write another `AGENTS.md` over that PR. After it merges, link it to this adapter and upstream spec. |
| GitHub executable issues | `.github/ISSUE_TEMPLATE/`, `tool/issue_task_hygiene.py`, `tool/issue_task_ci.py` | **Partial.** Pending PR #892 adds stricter hosted-runner issue contracts; legacy issues may still contain incomplete or manual criteria. |
| Issue acceptance manifests | `docs/acceptance/temporary/issue-N.json`, `docs/acceptance/TASK_LIFECYCLE.md`, `tool/acceptance_criteria.py` | **Implemented for mapped issues**, not the entire backlog. Exact named tests and nonempty evidence required for actual closure. |
| Selective CI | `tool/ci_impact.py`, `.github/workflows/ci.yml`, `docs/CI_SELECTIVITY.md` | **Implemented conservatively.** Unknown policy/build paths and `.factory/config.yaml` trigger full CI. Docs-only `docs/factory/*.md` skip unrelated native lanes. |
| Stable gate | Existing required aggregate `build` check | **Implemented existing name.** Do not rename to `factory-gate` without verifying branch protection and merge triggers. |
| Merge queue | Existing pull_request and push CI (not a configured merge_group gate) | **Not established.** Verify branch rules before enabling queue-specific requirements. |
| Automatic merging | Trusted `.github/workflows/issue-automation.yml` and `tool/issue_auto_merge.py` | **Partial.** Green CI can enable GitHub auto-merge for explicit `AutoClose #N`; current helper does **not** independently verify reviewer identity. |
| Verified closure | `tool/issue_auto_close.py` consumes successful main CI workflow_run and checks exact-head PR CI and full mapped acceptance | **Implemented for eligible mapped issues.** `Refs #N` may remain open across partial PRs; no native closing keywords. |
| Temporary gate retirement | JSON temporary/permanent mapping, documented promotion | **Partial.** Tests remain in regression; automatic retirement on issue closure is not generally deployed. Preserve manifests until safe migration. |
| Durable fenced task leases | `.team/` assignments and WIP process | **Not implemented.** Do not equate comments or assignees with atomic claims. |
| Stateless controller and worker runtime | Existing external managers/workers only | **Not deployed as a trusted self-running service.** Require external scheduler, durable claims and bounded recovery. |
| Resource policy / multi-agent budgets | `.team/roster.yml` WIP limits | **Partial.** Monetary/token limits and enforcement not deployed. |
| Protected workflow changes | Pinned actions in CI and dedicated `tool/check_workflow_trust.py` | **Partial.** Audit actual GitHub rules/permissions; don't assume agent-role prompt alone enforces them. |

## Current executable delivery contract

1. New requirements: write complete, objective and runner-checkable ACs in GitHub Issues. Hosted GitHub macOS/Linux/Windows runners and approved emulators/simulators are supported; physical hardware, private Macs and real TCC interactions are **not** valid autonomous completion evidence. Preserve unautomatable legacy gaps and never silently weaken the feature's definition.
2. PR links: use standalone `Refs #N` for partial or final work. Only a complete eligible PR may include `AutoClose #N` to opt into auto-merge after green CI. **Do not use native `Closes`, `Fixes`, or `Resolves`.**
3. Acceptance: `tool/issue_task_ci.py` checks issue ↔ manifest mapping. Tests must be real, named, executed, passing and non-skipped; `manual` or `gap` cannot close automatically.
4. CI: retain required `build` aggregate and current named compatibility checks. The impact planner handles changes to `.factory/config.yaml` as unknown shared policy and thus runs full CI, whereas this Markdown file alone is a docs-only fast path.
5. Merge and closure: observe actual required checks and reviews. Trusted workflow may enable auto-merge for complete `AutoClose` candidates; `tool/issue_auto_close.py` closes only after successful main CI on the merge SHA with complete acceptance. Neither green PR CI nor merge alone proves all issue requirements.
6. Agent safety: never execute arbitrary code from issue/PR bodies with privileged tokens. Preserve pinned checkout `11d5960a326750d5838078e36cf38b85af677262` and pinned Flutter action `1a449444c387b1966244ae4d4f8c696479add0b2`. Do not reformat Dart automatically while implementing this documentation-only alignment.
7. Production invariants: changes to `WorkflowExecution._run()` and the approval-host prologue must preserve **synchronous prompt attachment** and keep the offline-prompt-fails-closed regression green. Privacy, observation, local-only and permissions rules in `docs/adr/ADR-001-bluey-delivery-decisions.md` remain authoritative.

## Migration backlog (separate reviewed changes)

1. **After #892 is green and merged:** add a link from `AGENTS.md` to this document and the adapter; resolve stale vendored `.team/` guidance upstream rather than overwriting its copy. Retain `Refs`/post-main closure semantics.
2. Add a trusted schema-driven `.factory` adapter validation lane, without installing heavy toolchains for documentation-only diffs. Verify policy changes trigger full/fail-closed routing.
3. Migrate issue criteria incrementally to safe validator IDs/targets (no shell from issue text); maintain existing JSON manifest support until verified equivalent.
4. Establish independent review enforcement (credential/ruleset identity), current-head and optional merge-group SHA integrity before upgrading merge automation.
5. Implement issue-gate retirement only once default-branch acceptance evidence is complete and ordinary regression selection retains equivalent tests.
6. Integrate trusted fenced leases, durable controller, resource budgets, state reconciliation and synthetic/live canary proofs **after** portable kit capabilities land and are independently reviewed.
7. Keep expensive physical-device/TCC acceptance outside automatic runner-only completion; split blocked requirements rather than closing them on simulation evidence.

## Local checks

```bash
python3 -m unittest discover -s tool -p test_ci_impact.py
python3 -m unittest discover -s tool -p test_issue_task_ci.py
python3 -m unittest discover -s tool -p test_issue_auto_merge.py
python3 -m unittest discover -s tool -p test_issue_auto_close.py
```

The above tests verify existing components; they do not prove a continuous controller or live GitHub merge settings. The portable config validator currently lives in agent-team-kit, pending vendoring/wiring into this repository.
