# Flaky test policy proposal

Audit 2026-10-11, main `387db52`. Refs #602. **DRAFT/UNADOPTED**, not actual quarantine, retry, skip or reporting gate. Fresh #593 prerequisite remains OPEN/unassigned. Sole new doc; no workflow/test/source/threshold/security/schedule change, installed tool, shared README/architecture/acceptance-map edit or suppressed required failure. Owner merge, native/paid/self-hosted #160/privacy #351/retained-operation gates remain separate.

## Decision and evidence

Keep required failures visible and failing. Diagnose before labelling a test flaky; a passing rerun doesn't prove root cause or repair. Proposed time-limited exceptions need explicit manager disposition plus owner approval when changing user-approved acceptance/security/paid or native execution. This draft grants no exception, chooses no retry budget and makes no test flaky allegation. No workflow rerun, disable, quarantine or new scheduled test was performed.

Complete current [CI](../.github/workflows/ci.yml)/other workflows, [test_report](../tool/test_report.dart), [metrics](../tool/ci_metrics.py)/[four fixtures](../tool/test_ci_metrics.py), [transport retry](../lib/llm/retry.dart)/[provider fixtures](../test/provider_retry_test.dart), explicit skip sites and prior [CI audit](CI_WORKFLOW_AUDIT.md) read. Search found no dart_test.yaml retry config, test retry annotation or workflow rerun/quarantine lane. UI/tutorial '.skip' methods and provider retry tests are app behavior, not disabled tests or failing-test reruns. Pending #601 reporting plan is separate/unaccepted input, not completed prerequisite.

| Current source | What it actually does | Not evidence of |
| --- | --- | --- |
| CI concurrency | ci-ref, cancel-in-progress true; current superseding run can cancel older run | An assertion failure or nondeterminism. Cancellation must keep its reason and SHA/attempt. |
| Android matrix |29/34, fail-fast false | Automatic retry. Failure in one platform is not erased by another green platform. |
| test_report.dart | Can list failed files from testDone result, comment mentions flaky-retry pass | Live CI wiring: expanded current test logs aren't that JSON input; no rerun lane. Ignores terminaldone/skips/lateError and cumulative time misreported as duration. |
| ci_metrics.py | Up to 100 runs/100 jobs, completed-job median, only failureconclusion in enumerated denominator | Complete flake statistics or causal classification. Cancelled/incomplete/skipped/API-unavailable differ; source sampling limits retained. |
| app withRetry | Default socket/timeout only,3 attempts,300/600ms; bounded 1..10 attempts/delay≤60s; predicates replace rule | Test quarantine, HTTPstatus/parse/programming retry, whole-call deadline/cancellation/idempotency/billing guarantee. |

Current explicit test skips found: [X11 integration](../test/linux_x11_integration_test.dart) unless BLUEY_X11_INTEGRATION=1; [local STT harness](../test/local_stt_tools_test.dart) on Windows; narrow mobile2x [onboarding pixels](../test/onboarding_completion_pixels_test.dart) unless opt-in pixels. These are environment/selected coverage exclusions, not adopted flaky quarantines. Current self-hosted native-validation is variable-gated and mocks native control even on Mac; skipped lane is not native acceptance. Do not enable any native/opt-in/capture path to call coverage complete in this plan.

Fresh live most recent 12 CI runs all completed success in the returned bounded sample, including [648 run](https://github.com/shpalac/local-bluey/actions/runs/38161490745) exacthead `b008f68` and [647 run](https://github.com/shpalac/local-bluey/actions/runs/38160751682) exacthead `562b560`. No flake rate, attempt-history completeness or universal reliability claim follows. No historic failure logs acquired, no same-test reproducibility investigation performed. Aggregate run success also doesn't mean every optional native job executed.

## Classification before any exception

Proposed immutable failure record: test id/source path+digest, source SHA/event/run/job/matrix/attempt, runner/toolchain/lock/config, phase and original exit, structured assertion/error/timeout/cancelled/malformed/missing evidence, sanitized failure signature, observed reproduction count and scope, assigned owner, linked investigation, policy revision. Assertion failure versus setup/install/network infrastructure, cancelled supersession, timeout, unsupported platform, skipped, missing report and malformed input remain distinct. Unverified root cause stays unknown; never infer 'infra' from transport-sounding text.

A flake candidate requires contradictory outcomes under declared equivalent test/input/source/runner/config conditions and preserved first failure, not green after unrelated fix/new commit or missing report. Even that is evidence of variability, not proof harmlessness. Separate actual production transport retry behavior from test-runner re-execution. Use controlled fake clocks/completers and exact state receipts before increasing sleeps or broad timeouts. Don't relax a safety/privacy/security assertion because it is expensive to diagnose.

[Dart config](https://github.com/dart-lang/test/blob/master/pkgs/test/doc/configuration.md) supports skip reasons and integer failure retry, but tool capability isn't adoption. [Dart test guide](https://github.com/dart-lang/test/blob/master/pkgs/test/README.md) describes concurrency/randomized-order seeds/reporting/platform selection. Later reproducibility record should fix relevant seed/order/concurrency/tool versions and isolate state; no arbitrary randomized rerun or retry added here. Mutable docs must be matched to pinned test runner before implementation.

[GitHub reruns](https://docs.github.com/en/actions/managing-workflow-runs/re-running-workflows-and-jobs) reuse original actor privileges and SHA/ref. A new run attempt isn't a new source fix or different authorization, and an API rerun capability isn't permission to spend runners, expose secrets or execute native/self-hosted work. [Concurrency guidance](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency) explains pending/supersession cancellation; record actual repo ci-ref behavior, don't adopt new queue policy from examples.

## Proposed exception lifecycle

Later proposal record, if selected: exact tests/platforms/policy, original failure evidence and reproduction instructions, owner+reviewer, narrow reason/risk/coverage gap, required equivalent coverage or compensating gate, finite expiry condition/date, repair criteria and tracked reactivation. Requested, rejected, approved-but-not-applied, active, expired, repair-under-review and reactivated are distinct. No permanent wildcard/filewide quiet exclusion; full file isn't one test. Approval must name the actual change, never a generic 'flaky' label.

This plan cannot decide whether any required acceptance may be quarantined. If a missing test would violate original user-approved acceptance, pause for its owner decision; manager prepares scope/risk and alternative rather than silently green merge. No applicable exception exists here. Failed mandatory safety/privacy/gate evidence stays blocking until accepted repair or explicit source-grounded scope change. Temporary runner unavailability is unavailable, not approved skip.

A later offline policy evaluator can check exact evidence/owner/scope/expiry and produce eligible/rejected/incomplete/expired, but must not disable tests or rerun. Evaluation pins schema/policy and stable component hashes; diagnostic timestamps separate, expiry uses explicit clock/timezone. Missing/invalid clock or evidence fails unknown; stale policy/changed test/source invalidates approval. Required failure status and original attempt remain immutable even if diagnostic repeat passes. No retry budget guessed in this draft.

## Reproduction, expiry and reactivation

Proposed approved diagnostic replay, if separately selected, uses exact inputs/source/runner and bounded attempts; retain every result and first failure. If fixed source differs, mark new revision and test both original regression and new repair. Test ordering/parallel/global state/cache/image drift are hypotheses until verified. No 'rerun until green', delete artifacts, swallow exceptions, continue-on-error or increase timeout to mask evidence. Owned child/process cleanup needs actual exit receipt; signal dispatch alone isn't stopped.

Expiry must be enforced by reviewed configuration/evaluator eventually, not a calendar note the user must track. Active exception remains visible with owner/deadline/gap, renewal is a new reviewed decision with fresh evidence, expired/missing entry blocks rather than becoming indefinite skip. Reactivation requires selected original-regression/negative/order/race/timeout/restart evidence, full relevant platform/source context and reviewed removal of exclusion; finite all-green sample isn't universal stability. Automatic expiry must not silently launch owner-native or paid tests.

## Failure reporting, privacy and rollback

Report run outcome independent of parser/artifact outcome. Missing or truncated terminal stream, lateError, cancelled attempt and parser error cannot produce zero failures/complete success. Existing test_report gaps are source findings, not fixed here. Logs 7 days/coverage 14 days in current CI; coverage upload default doesn't run after failure, test log always attempts upload. Retention/upload isn't permanent history or sanitized guarantees. Store narrow metadata/signatures/hashes, not credentials, raw user screen/audio/private paths/stack dumps. Fake tests do not prove every failure log harmless.

Cancellation fences stale result against current run generation, atomic publication preserves partial status; cleanup only owned temp files/child. Offline detector gets fabricated inputs, no network/CI mutating action. A later report may link safe source receipt and coverage gap but cannot send private diagnostic content without its scope. No repeated external monitor/quarantine reminder created here.

Rollback of a proposed tool/policy change is independently reviewed and preserves original test failure/coverage thresholds. Return to prior reviewed config only after compatibility/source evidence; never make required checks optional or clear history to 'restore velocity'. A failed repair leaves investigation and expiry visible, not a renamed test escaping quarantine. No source/CI rollback performed here.

## Tiny negative fixtures and gates

Future inert fixtures: deterministicfailure versus same-source divergent result, newSHA not same reproduction, wrong runner/seed/platform, missing report/lateError/cancelled supersession, malformed retry input/expired clock/owner missing/wildcard scope, safety assertion proposed exception denied, renewal absent, changed policy/testdigest, reactivation without original regression, passing diagnostic does not overwrite failed required attempt, held cleanup and stale publication. They prove classification/lifecycle, not true root cause/actual environment stability. No new committed tests or evaluator in this doc.

**69 unchanged Dart+4 unchanged offline Python tests passed, 0 new**: dartdoc_contracts,privacy_plists,retry,provider_retry and actual ci_metrics fixtures. Analyze clean,format 273 files/0 changed,diff clean. Provider fake typed retries don't prove flaky-test policy, actual HTTP delivery or native acceptance. No whole-suite/new quarantine execution.

Current exact-head static/test/linux/security/docs and manager APPROVED remain PR gates. #593 unresolved, #601 reporting plan unaccepted, owner acceptance/native/privacy/paid gates intact. Refs-only/issue open/no immediate owner ask. Future missing selections: reliable attempt report schema, exception authority/coverage/expiry/repair conditions, diagnostic budget and maintained ownership; no policy secretly adopted.

## Primary references

Fetched 2026-10-11; complete relevant sections inspected. Current source and bounded live runs versus primary capability docs clearly separated. External examples are not authorization.

- [Dart configuration](https://github.com/dart-lang/test/blob/master/pkgs/test/doc/configuration.md): explicit retry/skip capability, no selected config.
- [Dart guide](https://github.com/dart-lang/test/blob/master/pkgs/test/README.md): seeds/concurrency/reporting/platform scope.
- [GitHub reruns](https://docs.github.com/en/actions/managing-workflow-runs/re-running-workflows-and-jobs): original actor/SHA/ref and bounded platform capability, not approval here.
- [GitHub concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency): supersession differs from failure/root cause.
- Exact project workflows/tools/app retry/skip fixtures/prior audit and two observed runs above: current source behavior/sampling, not a complete flake inventory.
