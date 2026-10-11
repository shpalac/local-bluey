# Test reporting evidence plan

Audit 2026-10-11, main `387db52`. Refs #601. **DRAFT first-stage preparation**, not an installed JUnit/coverage gate or completed #601 acceptance. Fresh #593 full body OPEN/unassigned; prerequisite unresolved. Sole new doc, no workflow/tool/source/threshold/security/schedule/install change or shared README/architecture/acceptance-map edit. Existing owner merge/paid/self-hosted #160/native/privacy #351/retained-operation gates remain held.

## Result

Reuse existing logs, coverage floors and metrics fixtures, but bind structured results to the exact run and preserve failed/cancelled/missing/malformed states. Current CI does not invoke the JSON summary tool or publish JUnit. No new converter or reporting policy selected/implemented. A pretty summary, artifact upload or successful retry must not replace the original test exit and incomplete evidence.

Complete [test_report.dart](../tool/test_report.dart), [check_coverage.dart](../tool/check_coverage.dart), [ci_metrics.py](../tool/ci_metrics.py)/[four fixtures](../tool/test_ci_metrics.py), five workflows and prior [CI audit](CI_WORKFLOW_AUDIT.md) reviewed. No test_report/check_coverage-specific tracked fixture file found by source search; that is a gap, not permission to add one here. Fresh open PR list contains #607 release preparation, no overlapping reporting PR. #602 quarantine proposal stays separate; reporting does not authorize rerun/skip/adopted policy.

| Current owner | Actual behavior | Source-grounded gap |
| --- | --- | --- |
| CI test | Flutter test --coverage --reporter expanded, pipefail+tee,8 min step; coverage check follows | Expanded log, no JSON file/JUnit invocation. Test failure stops later default steps, including coverage check/upload. Test log upload has always(); coverage upload does not. |
| test_report.dart | Reads JSONL, suite/id/name joins; nonhidden testDone count; failure/error result set; Markdown slowest 10, --failed-files list | Event.time stored as duration and summed although elapsed since runner start. Ignores terminaldone/protocolversion/skipped/lateError. No XML, no workflow invocation, no dedicated structured failure exit. Comment 'flaky-retry pass' not a live retry lane. |
| check_coverage.dart | lib/services 60%,lib/link 65% LF/LH floors; missing file exit 2, low/zero denominator exit 1 | Prefix-relative source paths only, no DA/branch/function/source-hash validation, no duplicate/overcount integrity, no trend/history or whole-source coverage guarantee. |
| ci_metrics.py |100 runs/100 jobs max,APIerrors explicit; completed job duration medians; normalizes API matrix suffix | No pagination, docs/simulator omitted, failure-rate denominator includes enumerated noncompleted/cancelled, only failureconclusion counted. Sample not full reliability or flake classification. |
| metrics workflow |4 offline fixtures, runs weekly/dispatch, summary marked incomplete and job failed on API errors; ≥5 runs/>20% issue | Existing schedule/issues permission, no dispatch or policy change. Empty valid sample differs from failed enumeration; no JUnit/coverage trend artifact. |

CI test coverage artifact 14 days, expanded test log 7 days(always); failure Mac/iOS/Android build logs 3 days, simulator screenshot 14 days(always attempted), Linux tar/bundle 14 days, release staging 7 days. No general artifact scrub step. A skipped upload or missing file isn't available failed-run evidence. Current retention definitions aren't verified durable availability/permission or automatic privacy guarantees. No artifact downloaded or raw user log acquired for this plan.

## Reproducible characterization, not new committed fixtures

Private tiny fabricated files were run through the existing tools unchanged: suite/testStart(time100)/successful testDone(time200)/lateError(time210), with no terminaldone, prints '1tests,0failed,0.2s total' and exit 0. It should not be trusted as complete success: [Dart protocol](https://raw.githubusercontent.com/dart-lang/test/master/pkgs/test/doc/json_reporter.md) defines elapsed event time and late errors as failure, done.success=null as incomplete. Actual test runtime in that fixture is100 ms, not200 ms. No secrets/network/native input or real failed run used.

Second fabricated LCOV has servicesLF1/LH2 and linkLF1/LH1; unchanged coverage checker prints200%/100% and exit 0. It trusts aggregate integers, not coverage integrity. This is a concrete input-validation gap, not proof actual CI coverage is corrupted. No thresholds changed or production tool patched. These private characterization runs are **not new regression tests**, legal gate, production policy or whole-suite report.

## Proposed typed report contract

Later manager-selected fake-only slice: immutable run identity (repo/source SHA/event/workflow/job/matrix/runId/attempt), toolchain/lock/schema/parser policy revision, input content hashes, expected suite inventory and output completeness. Keep run outcome separate from report outcome: tests success/failure/error/cancelled/timedout/unknown; report valid/incomplete/malformed/unsupported/serializationFailed/uploadUnavailable. Green requires complete expected input and independently preserved original process outcome, never a missing report read as zero failures.

Parse bounded UTF-8 JSONL with required start/version, opaque run-scoped suite/test IDs, valid schema/types/time and explicit terminaldone. Interleaved events allowed, lateError after testDone changes outcome; hidden loader failures become visible, skip stays skip, duplicate names don't overwrite distinct IDs. Unknown additive fields safe, unsupported/new state needs explicit version policy, not success. Track actual start/end elapsed duration per id; aggregate walltime and summed per-test work distinct under concurrency. Bounded size/event count/path refs, no dynamic code/remote fetch.

JUnit isn't one universal authoritative dialect. [Ant-oriented WindyRoad schema](https://github.com/windyroad/JUnit-Schema/blob/master/JUnit.xsd) and [Jenkins-oriented Cucumber schema](https://github.com/cucumber/junit-xml-formatter/blob/main/jenkins-junit.xsd) show different consumer expectations; choose/pin the target consumer+schema, roundtrip representative fixtures, preserve failure/error/skipped distinctions and counts. XML-escape all names/text/attributes, reject forbidden control bytes, deterministic sort and numeric seconds, no XML external entity/network retrieval. Don't place raw stack/output/environment secrets in system-out/properties. Unknown duration unavailable, not fake zero.

[LCOV pinned manual](https://github.com/linux-test-project/lcov/blob/751a06367107e0134c8bce2ea1b89e1f8d10ea35/man/geninfo.1) distinguishes sourceSF, lineDA/LF/LH, branchBRDA and end_of_record. A later validator must normalize source paths against exact allowed checkout, reject traversal/outside/symlink ambiguity, malformed/negative/inconsistent totals and duplicates, pin intended coverage producer version. Define exclusions and measured file inventory, verify input/source hash and preserve absent files. Lines/branches/functions cannot be called equivalent coverage. Current floors remain unchanged; trend compares same scope/toolchain/policy, not unlike missing reports or samples.

## Failure, cancellation and privacy

Original test failure remains failing even when report conversion/upload succeeds. A report conversion error also gets explicit status without overwriting the original exit. If runner/job cancelled/timed out, partial stream is incomplete even if all observed testDone successful; don't invent unseen expected suites or terminal receipt. Proposed finally-style publishing can attempt a bounded sanitized failure summary, but upload availability cannot be promised after forced runner cancellation. No continue-on-error/retry/always configuration changed here.

Identity-bound partial output is atomically staged; cancellation/late result fence prevents old report replacing new attempt. Clean only owned temporary files. Read/parse/serialize/upload timeout and actual completion receipt distinct, no success from signal dispatch. Stable sanitized component keys/hashes and sorted outcomes produce repeatable decision digest; timestamps diagnostic. Missing data stays unavailable, not 0%/100%/green; old report marked stale, not reused as current.

Allowlisted diagnostics only: source SHA, phase/status, safe test key, error class, bounded sanitized evidence reference. Names/assertion text/stack traces and artifacts may contain private data, paths/tokens/screenshots; escape isn't sanitization. No raw screenshot/audio/user file/systemout export here. [GitHub artifacts](https://docs.github.com/en/actions/using-workflows/storing-workflow-data-as-artifacts) retention capped by repository/org/enterprise policy; upload/download SHA digest mismatch can be a warning, not a required-gate failure. Later workflow must select stricter expected digest/identity behavior explicitly, never assume checksum means publisher/source authenticity.

## Negative fixtures, rollout and rollback

Proposed tiny fabricated streams: interleaved same-named tests, hidden loader success versus late failure, failure/error/skip, absent/null done, malformed/truncated JSON/wrongtype/unknownprotocol, negative time/duplicate IDs, lateError, cancelled held read/write, stale attempt, missing suite/inconsistent count. JUnit: XML metacharacters/nonASCII/forbidden bytes, distinct failure/error/skip and consumer validation. LCOV: absent/empty/absolute/duplicate/outside file, LF0/LH>LF/negative malformed totals, source drift/missing file/branch-only/unmeasured scope. Upload/retention/digest warning/missing artifact failures injected, no network or live CI rerun.

First source-only parser/result fixture slice, then deterministic consumer-selected rendering, then selected reporting workflow integration only after #593 and manager review. No adoption/gate in this plan. Failures must remain actionable; any later report-tool rollback retains original test/coverage required checks, not a 'temporarily green' threshold/skip bypass. Do not overwrite failure history with a passing rerun; #602 owns any quarantine decision. Fix source/context first, preserve sanitized failed attempt; choose prior reviewed tool/policy only with exact compatibility and tests.

## Fresh checks and remaining gates

**18 unchanged Dart+4 unchanged offline Python tests passed, 0 new**: dartdoc_contracts,privacy_plists and actual ci_metrics fixtures. Analyze clean;format 273 files/0 changed;diff clean. Two private characterization commands above separate from test count. No whole-suite/native/device/JUnit consumer/trend/privacy guarantee. Current exact-head static/test/linux/security/docs and manager APPROVED remain PR gates; issue remains OPEN/Refs-only.

Issue #593 remains unresolved, future test-result consumer/schema/scope/privacy/retention selection still needed. Existing test exit/coverage thresholds intact. No immediate owner ask or schedule/rerun/permission/policy change. Prior accepted CI/license/provenance/native docs are research inputs, not complete reporting acceptance.

## Sources

Fetched 2026-10-11, complete relevant sections inspected. Project source/unchanged private fixture results and official/repository primary protocol/schema/manual/artifact docs. Mutable schema/protocol pages need exact version pin before implementation; external examples grant no execution authority.

- [Dart JSON protocol](https://raw.githubusercontent.com/dart-lang/test/master/pkgs/test/doc/json_reporter.md): cumulative time/interleaving/lateError/hidden/skip/null terminal outcome.
- [WindyRoad Ant JUnit](https://github.com/windyroad/JUnit-Schema/blob/master/JUnit.xsd) and [Cucumber Jenkins schema](https://github.com/cucumber/junit-xml-formatter/blob/main/jenkins-junit.xsd): consumer-specific XML counts/seconds/results, not one universal schema approval.
- [Pinned LCOV manual](https://github.com/linux-test-project/lcov/blob/751a06367107e0134c8bce2ea1b89e1f8d10ea35/man/geninfo.1): source/line/branch/record semantics.
- [GitHub artifact guidance](https://docs.github.com/en/actions/using-workflows/storing-workflow-data-as-artifacts): retention limits and checksum-warning behavior, not privacy/authenticity certification.
- Project tools/workflows/fixtures/prior audit linked above: current coverage and precise unimplemented gaps.
