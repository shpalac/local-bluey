# Performance baseline, issue #617

The production latency-summary entrypoint is `dart tool/perf_summary.dart <perf.jsonl>`. It reports per-stage nearest-rank p50/p95 milliseconds, sorted by stage, from nonnegative integer samples. The optional stage name must be a nonempty ASCII identifier comprising letters, digits, underscore, dot or hyphen. This rejects CSV delimiters and formula-leading characters; malformed records fail with exit code 2 and a line number without replaying input contents.

Deterministic CI fixture: `flutter test test/perf_summary_test.dart test/perf_summary_stage_validation_test.dart`. The results describe supplied synthetic or captured latency samples, not measured host CPU, RAM, disk or cold start. No numeric device budgets have been established; measuring and approving p50/p95 latency, CPU, RAM, disk and cold-start thresholds across target hardware remains a gap.

Privacy: do not include identifiers, secrets or user content in stage names or committed benchmark samples. Arbitrary input provenance and CI artifact access require manual review. Routines and native platform compatibility also require separate integration/manual evidence. This CLI never invokes a host action or network API.

Rollback: revert the stage-label validation change and its focused regression test. No persistent or platform state is written by this change.
