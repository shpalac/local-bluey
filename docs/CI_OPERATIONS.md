# CI operation and evidence

## Pull requests and main

`CI` always reports `ci-required`; `CodeQL` always reports `codeql-required`.
Do not put a workflow-level path filter on these required workflows.
The classifier uses the PR merge-base diff or the push before/after diff.
Unknown inputs and unavailable ancestors select every lane; deleted inputs
are included. Documentation-only changes run control/reporting fixtures,
workflow lint and vulnerability/secret scans. README/user-guide/site changes
also run the focused privacy-documentation contract, without native builds.

Dart/application changes select all client builds and emulator contracts.
Test-only changes select the Dart test lane. Native platform changes select
that platform; dependency, toolchain and workflow changes select all lanes.
CodeQL skips native scans for Dart-only changes and scans both languages on
its weekly schedule. The iOS simulator starts alongside selected builds.

The compatibility `build` check requires each selected Apple build.
`ci-required` requires every selected lane; an expected skip, missing result,
failure or cancellation fails the gate. Intentionally unselected jobs may
be skipped. Do not replace a failed result with a passing retry.

## Structured reports

The unit/widget lane writes the Flutter JSON protocol 0.1.1 to
`test-report.jsonl` while retaining the expanded `test-output.log`.
`tool/test_report.py` renders `test-results.xml` and `test-summary.md`.
Per-test durations are completion minus start, not cumulative runner time.
Skipped tests and hidden loader errors remain distinct. Missing/malformed
terminal evidence or unfinished tests fail reporting; the original Flutter
exit code remains independently required. A per-test 90-second timeout
bounds hangs without raising the eight-minute unit/widget step budget.
Coverage floors remain 60% for services and 65% for link.

Reports and coverage are attempted after failure. Logs/structured unit
reports have seven-day retention, coverage fourteen days, emulator JSON
seven days, and release-test evidence fourteen days. Raw logs may contain
fixture diagnostics; do not put real credentials, recordings or screen
content into CI tests. The summary/XML omits raw stack traces.

## Evidence boundaries

- Unit/widget tests: mocked contracts and deterministic golden comparisons.
- Android APIs 29/34: emulator gesture/LLM contracts with a mocked native
  MethodChannel; no physical microphone, STT or real Mac input proof.
- iOS simulator: build, installation and ten-second process survival.
- Linux lane: real loopback pairing and X11 pointer movement under Xvfb,
  plus a release build; not physical-device permission evidence.
- Manual native workflow: mocked macOS integration contracts plus signed
  host readiness checks. It does not claim an automated real audio/STT/input
  end-to-end result. That still needs a provisioned, consented physical host.

## Administrative setup after merge

The GitHub connector cannot read or modify branch protection or environment
protection settings. A repository administrator must perform these steps:

1. Require `ci-required` and `codeql-required` on main after their first runs.
   Existing required job names are retained for compatibility. Review older
   individual checks rather than silently removing them.
2. Create the `native-validation` environment, restrict deployment to main,
   add required reviewers and disable approval bypass if available.
3. Register an isolated self-hosted Mac with labels `self-hosted, macos`.
   Install the signed app and grant only the needed permissions. Install
   the readiness script's Python/Pillow prerequisites.
4. Only then set `ENABLE_NATIVE_VALIDATION=true` and dispatch the manual
   workflow on main. Never add a PR trigger to this signed-host workflow.

No self-hosted runner is provisioned or enabled by this change.

## Release and screenshots

Release tags must match pubspec. macOS/iOS build on macOS; Android and Linux
build on Ubuntu. Android uses Temurin 21. Four deterministic artifacts have
individual SHA-256 files, checked before publication, and provenance
attestations. iOS remains unsigned; this does not add notarization or store
publication. No release tag is created to test the pipeline.

README screenshot PR runs are read-only artifacts from the exact head SHA.
They never push a commit that causes an approval-required bot PR run.
For the existing README branch, manually dispatch `README showcase
screenshots` with `publish=true` to request a commit. Publication checks the
original SHA, uses a normal fast-forward push, and keeps an artifact when
concurrent edits make the output stale. Never force-push generated output.
