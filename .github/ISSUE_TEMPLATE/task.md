---
name: Task
about: A scoped deliverable with acceptance criteria provable on GitHub-hosted runners
labels: task
---

## Objective

Describe the observable behavior/result that must change.

## Scope

- In scope:
- Out of scope:
- Dependencies:

## Acceptance criteria

- [ ] AC-1: Given <state>, when <action>, then <observable, runner-testable result>.
- [ ] AC-2: Given <negative/edge case>, when <action>, then <safe, runner-testable result>.

## CI and validation

- GitHub-hosted runner: ubuntu-latest
- AC-1: test/issues/issue_<number>_test.dart — <exact proposed assertion and test name>.
- AC-2: test/issues/issue_<number>_test.dart — <exact proposed assertion and test name>.
- Issue manifest after implementation: docs/acceptance/temporary/issue-<number>.json
- Add integration_test/features/<feature>_test.dart and a permanent manifest when user-journey coverage is relevant.

## Non-goals and runner limits

Explicitly exclude any real-device, physical Mac, interactive permission/TCC, human sign-off or unavailable-hardware validation. Those MUST NOT appear as acceptance criteria. If indispensable for safe delivery, scope separately and flag as blocked rather than falsely certifying them.

## Definition of done

- [ ] Every live AC maps to its own named automated test in a temporary or permanent manifest.
- [ ] Named tests execute successfully on GitHub-hosted CI at the exact PR head (no skipped tests).
- [ ] Required PR CI passes; post-merge main CI succeeds before automatic issue closure.
- [ ] No uncovered/manual/gap acceptance rows are silently considered complete.
