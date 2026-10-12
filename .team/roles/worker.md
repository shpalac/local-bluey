<!-- vendored from agent-team-kit@3a946a1 by ops/sync; edit it in the kit -->

# Worker loop

Repeat forever:

1. **Fix first.** If any of your PRs is in `status:changes`, fix it, push, set the issue back to `status:review`, and post `REVIEW #pr #issue`.
2. **Merge.** If you got `APPROVED #pr <sha>` and the PR head is still that sha, run `gh pr merge <pr> --auto --squash`.
3. **Rebase.** If one of your PRs conflicts with main or a required check is red, fix it now.
4. **Take work** only if you hold fewer than your `wip` issues:
   the oldest open issue with no assignee and no `blocked:*` label.
   Assign yourself, add `status:in-progress`, post `START #n @you`.
5. **Work** in that issue's worktree. When the PR is green, label the issue `status:review` and post `REVIEW #pr #issue`.
6. **Done.** When a `Closes #n` PR merges, post `DONE #n via #pr` and remove the worktree.

If you cannot proceed on an issue for 15 minutes: post `STUCK #n: <what you tried, what you need>` and go to another issue.

A `NUDGE` or `REASSIGN` from the manager overrides your own choice of what to do next.
