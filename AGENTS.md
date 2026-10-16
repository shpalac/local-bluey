# AI agent working contract

This repository is developed through GitHub Issues and pull requests. GitHub Issues are the source of truth for planned features, defects and tasks. Read this file **before creating or implementing an issue**. Detailed test/merge behavior is in [docs/acceptance/TASK_LIFECYCLE.md](docs/acceptance/TASK_LIFECYCLE.md).

## Opening an issue — mandatory

1. Inspect existing open issues, relevant code, CI workflows and related work; avoid duplicates.
2. Pick the Task, Feature request or Bug report template. State the observable objective, affected platforms, in-scope and out-of-scope behavior, dependencies, and sanitized reproduction (for bugs).
3. Specify the complete, bounded deliverable, including normal behavior, invalid inputs, offline/restart/cancellation, privacy/security, accessibility and regressions **where they are relevant and can be verified on GitHub-hosted runners**. Do not promise more than CI can prove.
4. Add a `## Acceptance criteria` section with consecutive `- [ ] AC-1: ...`, `AC-2: ...` statements. Each must describe one deterministic, observable behavior, not an implementation step or a claim that a mock certifies an actual device.
5. Add `## CI and validation`. Start with `- GitHub-hosted runner: ubuntu-latest` (and list `macos-latest` or `windows-latest` where appropriate). Add **one** explicit `- AC-N: ...` entry per criterion giving the planned executable test, assertion and runner. Use a concrete test file or test suite rather than generic “CI passes.” Each AC must have a distinct named automated test when implemented.
6. Add `## Non-goals and runner limits`. Real-device behavior, physical Macs, local hardware pairing, actual TCC prompts, interactive human approvals and other environments unavailable on GitHub-hosted runners belong here, **never as acceptance criteria**. If those are indispensable for a feature to be safe or correct, do not scope the feature as fully shippable; create a separately blocked item rather than certifying a simulated substitute.
7. Add a `## Definition of done`: a dedicated acceptance manifest matching the live AC identifiers, tests run successfully (not skipped) at the exact PR head, required CI green, and successful merged-main CI before automatic issue closure.
8. Do not invent existing tests, runner capabilities or unverified evidence. Never copy secrets, PII or production device data into issues or artifacts.

The issue creation workflow validates this contract and comments when it fails. AI agents must correct failed issue hygiene before beginning implementation. Existing legacy backlog follows migration guidance in the lifecycle document.

## PRs and completion

- Use **standalone** `Refs #N` for any incremental work. A merged Refs PR does not automatically mean the issue is done; the trusted post-main-CI closer rechecks complete issue evidence.
- Use standalone `AutoClose #N` **in addition to** `Refs #N` only when **all** acceptance criteria have exact named automated evidence in the temporary/permanent issue manifest and no manual or gap rows remain. This opts a green PR into GitHub squash auto-merge.
- **Never use GitHub-native `Closes #N`, `Fixes #N`, or `Resolves #N`.** Those can close the issue on merge, before merged-main CI and acceptance verification.
- An issue is marked completed only by the existing trusted `.github/workflows/issue-automation.yml` after successful CI for the exact PR head **and** exact main merge SHA and matching complete issue evidence.
- Security, privacy, human authorization and physical-device limits are **not** waived by a passing simulated test. Do not delete unmet criteria from an existing issue to force auto-closure.

## Team conventions

Agent assignment, WIP limits and status labels are described in `.team/`. If a vendored agent-team-kit protocol conflicts with this repository's issue acceptance and closure policy, use the stricter rule here and report the upstream discrepancy. Do not bypass required checks, approve your own PR, or claim CI proved unrun tests.
