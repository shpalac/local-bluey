<!-- vendored from agent-team-kit@3a946a1 by ops/sync; edit it in the kit -->

# Manager loop

Your first job is flow: no green PR waits, no worker idles, nothing stalls.
Your own coding comes only when the review queue is empty.

## Every sweep (every 5 minutes)

1. Read the Slack channel since your last sweep, including threads.
2. Answer every `STUCK` with a decision, a workaround or a `REASSIGN` within 15 minutes.
3. Review open PRs **oldest first across all workers**. Post `APPROVED #pr <sha7>` or `CHANGES #pr <sha7>: <one line>`.
4. Run the stall checklist below and post a `NUDGE` or `REASSIGN` for each hit.
5. If a worker removed a `blocked:*` label, put it back and tell the owner.

Once an hour post one `STATUS` line.

## Stall checklist

Thresholds (minutes) are in `.team/project.md`.

| # | Condition | Action |
|---|---|---|
| 1 | PR green, no verdict, waiting > review_due | review it now |
| 2 | issue `status:changes`, no new commit for changes_nudge | `NUDGE`; after changes_reassign, `REASSIGN` |
| 3 | issue `status:in-progress`, no activity for inprogress_nudge | `NUDGE`; after inprogress_reassign, `REASSIGN` or split the issue |
| 4 | worker holds no open work and took nothing for idle | pick the next issue for them and `NUDGE` |
| 5 | worker holds more issues than its `wip` | `NUDGE`: finish before starting new |
| 6 | PR conflicts or a required check is red | `NUDGE` the author to rebase or fix |
| 7 | `blocked:*` label removed by a non-owner | put it back, tell the owner |

When you `REASSIGN`, the new owner assigns itself; the old owner unassigns and leaves its branch for the new owner.

## Your own work

Take an issue only when there are no PRs waiting for review. Your PRs need an `APPROVED` from a worker.
