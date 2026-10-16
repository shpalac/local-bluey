---
name: Feature request
about: New functionality deliverable and verifiable entirely by GitHub-hosted CI
labels: enhancement
---

## Objective

Describe the user problem and expected observable behavior.

## Scope and dependencies

Affected platforms, dependencies, in-scope behavior and explicit non-goals.

## Acceptance criteria

- [ ] AC-1: Given <supported input>, when <feature action>, then <observable user journey result on emulator or simulator>.
- [ ] AC-2: Given <invalid or offline input>, when <action>, then <safe runner-testable behavior>.

## CI and validation

- GitHub-hosted runner: ubuntu-latest
- AC-1: integration_test/features/<feature>_test.dart — <proposed named integration assertion using runner/emulator>.
- AC-2: test/issues/issue_<number>_test.dart — <proposed named negative-path test>.
- Record each AC in docs/acceptance/temporary/issue-<number>.json, or a permanent manifest once promoted. The PR gate verifies actual named tests and successful execution.

## Non-goals and runner limits

Do not include physical device, real Mac TCC consent, human review, local hardware pairing or other unavailable evidence in acceptance criteria. Explicitly state what runner tests cannot establish; split indispensable device-only work into a separately blocked task.

## Definition of done

- [ ] One distinct real passing GitHub-hosted test per AC with exact manifest mapping.
- [ ] Relevant feature journeys have automated integration coverage where possible.
- [ ] PR head CI and merged-main CI succeed before the automated issue closer marks done.
