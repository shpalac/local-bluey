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

- Temporary issue-specific suite: `test/issues/issue_<number>_test.dart`.
- Register exact named cases in `docs/acceptance/temporary/issue-<number>.json`.
- For user-facing feature journeys, promote to `integration_test/features/<feature>_test.dart` and `docs/acceptance/permanent/issue-<number>.json`; pure-Dart contracts can close with complete temporary evidence.
- Remove temporary checks only after the permanent suite runs in CI; record any physical-device verification separately.

## Definition of done

- [ ] Every AC has a real named passing test and no manual/gap rows; PR CI passes at exact head and main CI passes after merge.
- [ ] Feature-level regression coverage exists when relevant, with documented limitations. Use `AutoClose #N` for automatic closure; `Refs #N` for partial work.
