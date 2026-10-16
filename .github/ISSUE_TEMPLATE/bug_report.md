---
name: Bug report
about: Reproducible defect and deterministic GitHub-hosted runner regression criteria
labels: bug
---

## Objective

Eliminate the failure without changing unrelated behavior.

## Environment and reproduction

- Affected platform and runner-reproducible environment:
- Observed:
- Expected:
- Sanitized reproduction steps:

## Acceptance criteria

- [ ] AC-1: Given <failing input/reproducer>, when <operation>, then <fixed runner-testable behavior>.
- [ ] AC-2: Given <related valid and invalid inputs>, when <operation>, then <no regression and safe failure>.

## CI and validation

- GitHub-hosted runner: ubuntu-latest
- AC-1: test/issues/issue_<number>_test.dart — <proposed exact failing-first regression test>.
- AC-2: test/issues/issue_<number>_test.dart — <proposed exact related regression test>.
- Use integration_test/features/<feature>_test.dart for runner-testable end-to-end flow regressions, and record exact tests in docs/acceptance/temporary/issue-<number>.json.

## Non-goals and runner limits

Exclude physical Mac/real iPhone/human approval/manual device-only checks from acceptance. A runner mock cannot certify an actual OS permission flow. If actual hardware evidence is indispensable, file separately as blocked rather than pretending acceptance is complete.

## Definition of done

- [ ] Targeted regression demonstrably fails before the fix when feasible and passes afterward.
- [ ] Each AC has a distinct executed named test on hosted CI, with no manual/gap evidence claimed green.
- [ ] Required PR CI and merged-main CI pass before verified automatic issue closure.
