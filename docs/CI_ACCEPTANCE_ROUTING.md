# Phase 3: manifest-driven issue acceptance

CI executes named tests from `docs/acceptance/temporary/issue-<N>.json`
(and permanent manifests when promoted). Each automated criterion declares
`{file, name}` references. The existing manifest loader validates paths and
test names; missing files or renamed tests fail CI.

## Sources of truth

- `tool/acceptance_criteria.py`: validates manifests, selects named cases,
  runs whole test files via Flutter's JSON reporter, and withholds raw output.
- `tool/issue_task_ci.py`: looks up the issues explicitly linked by a PR,
  validates their issue-specific manifests and executes selected unit tests.
- Specialist BLU-024 and BLU-034 workflows now invoke the manifest runner,
  rather than maintaining separate hand-picked Flutter test paths.
- Specialized offline Python STT regressions and platform builds remain separate,
  because they cannot be expressed as named Dart tests in schema version 1.

A passing automated lane means *only* that its selected automated cases ran and
passed. Manual/gap criteria remain incomplete. A PR claiming AutoClose must not
infer completion from a partial unit/integration execution; the issue gate now
rejects closure if the other test mode remains unevaluated. This does not replace
device reviews or sign-off.

## Validate

```shell
python3 -m unittest discover -s tool -p test_acceptance_criteria.py
python3 -m unittest discover -s tool -p test_issue_task_ci.py
python3 -m unittest discover -s tool -p test_acceptance_workflow_wiring.py
python3 tool/acceptance_criteria.py --manifest docs/acceptance/temporary/issue-580.json --run-tests --out-dir build/acceptance/blu-024
```

The last command requires Flutter and is exercised in its specialist CI lane.

## Rollback

Revert the phase-3 commit to restore hardcoded specialist suite invocations.
Do not delete issue manifests or acceptance evidence. Keep the stable required
CI `build` aggregate gate and its fail-closed acceptance dependency.
