# CI phase 4: faster, safer expensive lanes

## Preflight before costly platform jobs

The existing Ubuntu `static` job validates formatting, metrics fixtures,
and Flutter analysis before the macOS, iOS, Android, emulator, and Linux
build jobs begin. These platform jobs only run when impact routing selects
them and static preflight succeeds. The central `build` gate continues to
reject failures and unexpected skips. Full unit/widget tests still run
in parallel with static; native jobs do not wait for full-suite completion.

**Tradeoff:** successful PRs incur static-job latency before native builds,
but format/analyzer failures avoid spending costly emulator and macOS minutes.
Measure the effect on p50/p95 and runner-minutes before adjusting the policy.

## Impacted test files

`tool/ci_impacted_tests.py` validates the impact planner's JSON array:
paths must reference existing test files below `test/`, without duplicates,
symlink escapes, or unsafe characters. Missing/empty selections are failures.

The selected files run in **one** `flutter test --concurrency=6` invocation.
Flutter schedules those files concurrently. Previously two partitions were
started sequentially by Bash, causing duplicate startup and serialization.
`tool/ci_test_shards.dart` and its parity tests remain unchanged for
compatibility. Full-suite coverage and thresholds remain untouched.

## Checks / rollback

```
python3 -m unittest discover -s tool -p test_ci_impacted_tests.py
python3 -m unittest discover -s tool -p test_ci_speed_wiring.py
```

No new permissions, unpinned Actions, local runners, or secrets are used.
To restore native jobs' eager startup, revert the phase-4 CI workflow edit.
Do not remove the stable required `build` status.
