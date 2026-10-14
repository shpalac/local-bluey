## Objective

Describe the deliverable and its linked task issue. Use `Refs #<issue-number>` while work is incomplete. For full CI-driven closure, add a standalone `AutoClose #<issue-number>` line only when **all** original ACs have executable evidence and no manual/gap rows remain. GitHub-native `Closes` closes immediately on merge, before main CI; avoid it for this workflow.

## Scope and implementation

What changed and why? Note any migration, privacy/security considerations and rollback plan.

## Acceptance criteria evidence

| Issue criterion | Named automated test / manual evidence | Result |
| --- | --- | --- |
| AC-1 | | |
| AC-2 | | |

## Temporary acceptance CI

- [ ] Issue manifest exists at `docs/acceptance/temporary/issue-<number>.json` (unless already promoted).
- [ ] Tests directly exercise each applicable criterion, including negative paths; failing-first evidence recorded if feasible.
- [ ] Exact test files/names are in the manifest; skipped and failing tests do not count.

## Permanent integration (when relevant)

- [ ] Complete feature journey is tested under `integration_test/` when it is a user-facing flow requiring end-to-end coverage.
- [ ] If promoted, the permanent manifest maps the issue to named integration tests.
- [ ] If promoted, temporary manifest and redundant issue-only validation are removed.
- [ ] No unresolved hardware/manual criteria are claimed as automated or ready for AutoClose.

## Security, privacy and rollback

- [ ] No secrets, personal data or unsanitized logs in code, tests, fixtures or artifacts.
- [ ] No new network egress, permission or SafetyGate bypass; human approval paths are unchanged (or the change is described above).
- [ ] Rollback: describe how to revert this change safely (or write "revert the PR" if nothing is persisted).

## Manual and device-only evidence

List any criterion that hosted CI cannot prove (device, OS permission, hardware). Name the device, the evidence and the reviewer. Write "none" if all criteria are covered by automated tests. Hosted CI never proves these.

## CI and automatic closure

- [ ] Every live issue AC is mapped exactly once by ID in the temporary or permanent manifest, with no missing or extra criteria.
- [ ] `AutoClose #N` appears on its own line only for complete criteria; `Refs #N` is used otherwise.
- [ ] Auto-merge is activated after successful PR CI; issue closure runs after the matching merged-main CI succeeds.


- [ ] Existing repository tests, static analysis, security and platform builds pass.
- [ ] Issue task acceptance and emulator integration pass on the PR head.
- [ ] Acceptance and docs/traceability are updated; no privacy gate bypass or unapproved data egress.

