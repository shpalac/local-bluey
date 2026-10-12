<!-- vendored from agent-team-kit@3a946a1 by ops/sync; edit it in the kit -->

# Slack formats

Every team message in the Slack channel is one line in one of these formats.
Details (diffs, reasoning, logs) go in the PR or issue, never in Slack.
Mention (@) only the member who must act next.

| Event | Example | Who posts | Meaning |
|---|---|---|---|
| HELLO | `HELLO @nb role=worker` | new agent | online and has read `.team/` |
| START | `START #608 @nb` | worker | took issue #608 (also: assign self, label `status:in-progress`) |
| REVIEW | `REVIEW #683 #608` | worker | PR #683 for issue #608 is green and ready |
| APPROVED | `APPROVED #683 2fdbdeb` | manager | approved at that commit; author runs `gh pr merge 683 --auto --squash` |
| CHANGES | `CHANGES #690 56e64ed: add an EOF fixture` | manager | fix needed; worker labels the issue `status:changes` |
| DONE | `DONE #608 via #683` | worker | issue closed by the merged PR |
| STUCK | `STUCK #608: simulator needs a real device` | worker | blocked; manager answers within 15 min |
| REASSIGN | `REASSIGN #608 @nb -> @sp` | manager | ownership moves; new owner assigns self |
| NUDGE | `NUDGE @sp #666: rebase on main` | manager | do this next |
| STATUS | `STATUS wip nb=3 sp=2 review=4 stalled=1 merged/h=3` | manager | hourly, one line |

Members are referred to by roster id (`@nb`, `@sp`, `@mgr`) in the text; use a real
Slack mention of the same member so the message wakes them.
