# Selective pull-request CI

The central `.github/workflows/ci.yml` owns format, analysis, unit/widget tests,
security, affected platform builds and the fail-closed `build` merge gate.

## Compatibility and duplicate work

- `pr-fast-ci.yml` retains its original required-check name but now runs
  routing/gate regression tests without installing Flutter or re-running the
  full suite. Its independent status can be removed only after branch
  protection is verified and updated.
- `macos-native-build-lane.yml` retains its native XCTest coverage and
  runs Flutter `--config-only` rather than duplicating the Flutter macOS
  build and Dart unit tests already performed in central CI.
- `temp-issue-596.yml` keeps its original PR check, but a cheap Ubuntu
  detector skips its macOS job for unrelated PR changes.
- Specialized acceptance workflows remain available; their issue-specific
  tests must not disappear from required coverage when they are consolidated.

## Impact selection

`tool/ci_impact.py` uses a reverse Dart import/export/part graph for narrow
unit-test selection. Non-workflow modules can use this optimization only when
the selected source has mapped unit tests and is not reachable from an
application entrypoint or an integration test. Unknown paths, deleted tests,
test fixtures, core CI code, shared inputs and uncertain mappings fall back to
full CI. Every PR still requires acceptance evidence and security checks.

Known standalone workflows and CI metrics scripts route to their affected
lanes; unknown workflow and tooling files remain fail-closed.

## Verification

```bash
python3 -m unittest discover -s tool -p test_ci_impact.py
python3 -m unittest discover -s tool -p test_ci_gate.py
python3 -m unittest discover -s tool -p test_ci_consolidation.py
```

The CI change itself will run the full suite. Check the PR's selected lanes,
the stable `build` status and specialized acceptance statuses before merge.
If branch protection requires an obsolete name, keep its compatibility job
until settings can be changed. Revert the routing commit to restore previous
behavior without deleting any workflow history.

No physical-device validation is implied by a green CI result.
