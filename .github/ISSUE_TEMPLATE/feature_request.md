---
name: Feature request
about: New functionality described as a testable task
labels: enhancement
---

## Objective

Which user problem does this solve, and what behavior should result?

## Scope and dependencies

Describe affected platforms, non-goals and dependencies.

## Acceptance criteria

- [ ] AC-1: Given a supported starting state, the complete feature journey produces the expected observable result.
- [ ] AC-2: Invalid input, offline, permission denial, cancellation and restart behavior are tested where applicable.
- [ ] AC-3: Existing features, accessibility, localization and privacy/SafetyGate behavior do not regress.

## CI and validation

- Temporary issue-specific suite: \`test/issues/issue_<number>_test.dart\`.
- Register exact named cases in \`docs/acceptance/temporary/issue-<number>.json\`.
- Before closing, add permanent \`integration_test/features/<feature>_test.dart\` and \`docs/acceptance/permanent/issue-<number>.json\`.
- Remove temporary checks only after the permanent suite runs in CI; record any physical-device verification separately.

## Definition of done

- [ ] Required checks passed on the PR head; reviewers confirmed all applicable acceptance criteria.
- [ ] Permanent feature-level regression coverage exists, with documented limitations.
