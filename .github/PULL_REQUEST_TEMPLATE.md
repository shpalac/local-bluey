## Objective

Describe the deliverable and its linked task issue. Use \`Refs #123\` while work is in progress; \`Closes #123\` only when permanent integration evidence and all required reviews are complete.

## Scope and implementation

What changed and why? Note any migration, privacy/security considerations and rollback plan.

## Acceptance criteria evidence

| Issue criterion | Named automated test / manual evidence | Result |
| --- | --- | --- |
| AC-1 | | |
| AC-2 | | |

## Temporary acceptance CI

- [ ] Issue manifest exists at \`docs/acceptance/temporary/issue-<number>.json\` (unless already promoted).
- [ ] Tests directly exercise each applicable criterion, including negative paths; failing-first evidence recorded if feasible.
- [ ] Exact test files/names are in the manifest; skipped and failing tests do not count.

## Permanent integration

- [ ] Complete feature journey is tested under \`integration_test/\`.
- [ ] Permanent manifest maps the issue to named integration tests.
- [ ] Temporary manifest and redundant issue-only validation are removed after promotion.
- [ ] Hardware/manual criteria have separate reviewed evidence (or remain incomplete).

## CI and merge

- [ ] Existing repository tests, static analysis, security and platform builds pass.
- [ ] Issue task acceptance and emulator integration pass on the PR head.
- [ ] Acceptance and docs/traceability are updated; no privacy gate bypass or unapproved data egress.

