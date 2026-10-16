# Phase 5 — CI health and routing telemetry

The existing scheduled/dispatch-only CI metrics workflow reports p50 and p95
PR completion time (including queue time), runner-minutes by hosted OS, and
repeated setup step overhead relative to all measured runner time. Job-name
mapping is used only when GitHub doesn't return an OS label; unknown jobs
are kept in a separate bucket.

**Cache:** Flutter SDK action setup p50/p95 is a diagnostic proxy. Actions
run/job metadata does not expose actual cache-hit counts; the report must
not claim these are hit rates.

**Duplication:** repeated setup work is measured; no exact cross-workflow
duplicate-test count is inferred from jobs metadata alone. PRs selecting
all major lanes are a conservative proxy for broad routing, not proof of
duplicate execution. The impact planner emits bounded, non-sensitive reason
codes (`shared_config`, `shared_runtime`, `ci_tooling_or_integration`,
`unrecognized_path`, `unsafe_path`, `unmapped_or_fixture_tests`) and
selected lanes in each detect job's GitHub Step Summary.

## Validation

```bash
python3 -m unittest discover -s tool -p test_ci_metrics.py
python3 -m unittest discover -s tool -p test_ci_impact.py
```

Metrics read Actions metadata only, never logs or screenshots. The weekly
report intentionally fails when API pages hit their 100-record boundary
or jobs cannot be fetched; missing measurements are not silently zero.
Failure-rate alerts still require complete data.

Rollback: revert phase-5 changes. The central build merge gate, branch
protection, and acceptance evidence remain unchanged.
