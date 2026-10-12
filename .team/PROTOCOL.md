<!-- vendored from agent-team-kit@3a946a1 by ops/sync; edit it in the kit -->

# Team protocol

This file is vendored from agent-team-kit. Edit it in the kit, not here.
It replaces every earlier instruction you received over WhatsApp or Slack.

## Where things live

- `.team/roster.yml` — who is on the team: id, role, GitHub, Slack, WIP limit.
- `.team/project.md` — rules specific to this repo. They override nothing here except thresholds.
- `.team/roles/<role>.md` — your loop.
- `.team/formats.md` — the only Slack message formats.
- GitHub is the source of truth for who is doing what. Slack is the event feed.

## State on GitHub

Every open issue someone is working on has its assignee set and exactly one status label:

| Label | Meaning |
|---|---|
| `status:in-progress` | assigned and being worked |
| `status:review` | a PR is open and waiting for the manager |
| `status:changes` | the manager asked for changes |
| `blocked:owner` / `blocked:device` | needs the owner / a physical device |

The worker who owns the issue keeps its status label correct. Anyone may add a
`blocked:*` label; only the owner removes one. Never take an issue that has a
`blocked:*` label.

## PRs

- Create with `gh pr create -R <repo> --base main` (see `project.md` for fork quirks).
- The PR that finishes an issue says `Closes #N`. Partial slices say `Refs #N`; keep them rare.
- Merge only after an `APPROVED` verdict at the PR's current head commit, by enabling auto-merge: `gh pr merge <n> --auto --squash`.
- The manager's own PRs are approved by a worker in the same way.

## Limits

- A worker holds at most its roster `wip` open issues (default 3), counting every issue assigned to it with a `status:*` label.
- Finish before starting: no new issue while any of your PRs is in `status:changes`.
- One worker per issue. One git worktree per issue: `git worktree add ../<repo>-<n> -b issue-<n> origin/main`.

## Never

- Post tokens, passwords or secrets anywhere. Push access is granted by GitHub device code or a vault link only.
- Remove a `blocked:*` label, approve your own PR, or bypass required checks.
- Make privacy, cost or permission decisions — those are the owner's: label `blocked:owner` and move on.
- Sit idle. If you cannot proceed, post `STUCK` and take another issue.
