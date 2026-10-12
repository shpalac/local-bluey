---
name: Bug report
about: A reproducible defect with measurable acceptance and regression tests
labels: bug
---

## Objective

Eliminate the reported failure without changing unrelated behavior.

## Environment and reproduction

**Platform:** macOS host / iOS companion / Android companion / link layer

**Observed:** 

**Expected:** 

**Reproduction steps (sanitized):** 

## Acceptance criteria

- [ ] AC-1: The supplied reproduction fails before the fix and passes after it.
- [ ] AC-2: Similar valid operations continue to work; invalid inputs fail safely.
- [ ] AC-3: No privacy, security, localization, accessibility or supported-platform regression.

## CI and validation

- Add a targeted reproducer in `test/issues/issue_<number>_test.dart` and map its exact name in `docs/acceptance/temporary/issue-<number>.json`.
- When fixed, add an end-to-end regression in `integration_test/features/<feature>_test.dart` and move coverage to `docs/acceptance/permanent/issue-<number>.json`.
- Remove temporary CI evidence only after permanent integration validation is green; include real-device review where simulator checks are insufficient.

## Definition of done

- [ ] Regression test proves the original defect is repaired.
- [ ] Required CI and review pass; no unverified manual criterion is declared green.
