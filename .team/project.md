# Project notes: local-bluey

## Product decisions (owner-approved, ADR-001 / PR #651)

- Observation is opt-in. Sensitive frames fail closed.
- Data stays in memory until encryption at rest is verified.
- No automatic retry for non-idempotent actions.
- Local-only: no cloud fallback.
- Priority order P0 → P3 as in ADR-001.
- Anything touching privacy, cost, permissions or paid CI → label `blocked:owner` and move on.

## Repo quirks

- This repo is a fork: always `gh pr create -R shpalac/local-bluey --base main`.
- The manager's GitHub account (`shferents`) is currently restricted: it can push branches but its PRs and comments are invisible. A worker opens the manager's PRs; verdicts go in Slack.
- Northbeam has no Xcode: it takes only issues that can be built and verified on CI.
- #598 and other `blocked:owner` issues stay blocked until the owner says otherwise.

## Finish what is open first

On switch-over, about 25 issues were assigned and only partly done (PRs said `Refs #N`).
Before taking new issues, each worker finishes or hands back its open ones: either
land the remaining work with a `Closes #N` PR, or unassign the issue and remove its
status label so someone else can take it.

## CI

- Free plan: 5 concurrent macOS runners for the whole repo. Don't push to a PR more than needed; batch fixes.
- Required checks: static, test, linux, security, build-ios, build-macos, android. `simulator` and CodeQL are not required.
- CodeQL runs on PRs only for native paths (#677).

## Config

```yaml team-config
owner: shpalac
required_checks: [static, test, linux, security, build-ios, build-macos, android]
thresholds:
  review_due: 30
  changes_nudge: 60
  changes_reassign: 120
  inprogress_nudge: 90
  inprogress_reassign: 150
  idle: 20
```
