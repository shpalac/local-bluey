---
name: Task
about: A single deliverable with testable acceptance criteria and CI evidence
labels: task
---

## Objective

Describe the observable result and the user or system behavior that must change.

## Scope

- In scope:
- Out of scope:
- Dependencies:

## Acceptance criteria

- [ ] AC-1: Given <initial state>, when <action>, then <observable outcome>.
- [ ] AC-2: Failure, cancellation, offline, permissions and restart behavior is defined where relevant.
- [ ] AC-3: Existing workflows, privacy boundaries and platform support do not regress.

## CI and validation

- **Temporary issue test file:** `test/issues/issue_<number>_test.dart`
- **Temporary manifest:** `docs/acceptance/temporary/issue-<number>.json`
- **Required negative/edge tests:** Document applicable cases and explicitly justify exclusions.
- **Permanent feature integration test (when relevant):** `integration_test/features/<feature>_test.dart`
- **Permanent manifest (when promoted):** `docs/acceptance/permanent/issue-<number>.json`
- **Runner:** Ubuntu unit/widget and Android emulator integration; macOS/iOS where applicable.
- **Manual or device-only criteria:** Name the device, evidence and reviewer; never claim hosted CI proves them.

## Definition of done

- [ ] Every applicable acceptance criterion has observed evidence on the exact PR head.
- [ ] Temporary tests fail before the fix and pass afterwards (when feasible).
- [ ] Every AC is proven by temporary or permanent named tests; feature journeys have integration coverage when relevant.
- [ ] Temporary manifest and redundant temporary tests are removed only after promotion.
- [ ] Existing required CI and security checks pass. `AutoClose #N` enables automated squash merge and post-main-CI closure only when all ACs are automated.
- [ ] Docs, rollback notes and traceability are updated; any manual/device or implementation gap blocks automatic closure.
