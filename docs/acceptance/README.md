# Issue acceptance evidence (BLU backlog)

For the required task lifecycle, issue-linked temporary CI and promotion to permanent end-to-end tests, see [TASK_LIFECYCLE.md](TASK_LIFECYCLE.md). The existing manifest below remains a legacy baseline and is not evidence that every open issue has passed.

This is **bounded verification**, not automatic sign-off. CI now runs [BLU-001..003](BLU_001_003_AUDIT.md) from separate issue-specific manifests (`issue-554.json`, `issue-555.json`, `issue-556.json`) and uses `criteria.json` for #558, #563 and #608. It runs each named suite only once in its lane. The issue's actual acceptance criteria take precedence if they change.

## What CI proves

- `.github/workflows/ci.yml` runs `acceptance-evidence` on PRs and `main`. The BLU-001..003 dispatcher validates that `AC-1` to `AC-4` are explicitly represented, and rejects missing/renamed/skipped/failed test references. It runs the named tests on Flutter and generates issue-scoped sanitized evidence. Green means only the *automated* subset passed; native/manual conditions remain separately visible.
- The existing required `build` aggregate depends on `acceptance-evidence`, so a failing automated evidence gate blocks that required check as well. This does not require changing branch-protection settings.
- The check emits `build/acceptance/blu-001-003/{acceptance.md,acceptance.json}` and `build/acceptance/other-issues/{acceptance.md,acceptance.json}` with `passed`, `failed`, `manual_required`, or `not_implemented`. Artifacts include only bounded filenames, criterion IDs and rationale. Raw test stdout and fixture secrets are not included.
- A `manual_required` or `not_implemented` row is never counted as `passed`, regardless of neighboring suite results. Hardware security, OS permissions, model locality and human review require real evidence.
- Green CI **does not by itself close issues, grant privacy/security approval, enable vision capture or authorize persistent storage**. A fully automated `AutoClose #N` PR may close only after its exact-head CI, merge and merged-main CI have passed, and the live issue/manifest have no manual or implementation gaps.

## Review and completion procedure

1. Compare #554, #555, and #556 against their dedicated `issue-N.json` file, and the other issues against `criteria.json`. Update the applicable manifest when implementation changes; do not remove unmet criteria to make CI green.
2. Add an actual `test/..._test.dart` path and exact test name for each newly automated criterion. The validator fails if the test is removed or renamed. Run the entire file to avoid hiding neighboring regressions.
3. Change a `gap` to `automated` **only after the production integration exists** and a regression test exercises it. Keep `manual` until a reviewer records build/device/OS, actions, outcomes, commit SHA and evidence URL.
4. For complete issue-specific temporary or permanent manifests, use a standalone `AutoClose #N` line in the PR body. The trusted workflow enables auto-merge only after green PR CI; then it revalidates evidence and closes the issue after successful CI on `main`. Keep `Refs #N` for partial work. Native/manual criteria and gaps still block automation.

## Local commands

```sh
python3 -m unittest discover -s tool -p 'test_acceptance_criteria.py'
python3 -m unittest discover -s tool -p 'test_blu_001_003_acceptance.py'
python3 tool/blu_001_003_acceptance.py --out-dir build/acceptance/blu-001-003
python3 tool/acceptance_criteria.py --out-dir build/acceptance/other-issues
flutter pub get --enforce-lockfile
python3 tool/blu_001_003_acceptance.py --run-tests --out-dir build/acceptance/blu-001-003
python3 tool/acceptance_criteria.py --run-tests --out-dir build/acceptance/other-issues
```

Without `--run-tests`, automated rows say `not_run` rather than `passed`. A failing Flutter test yields only a sanitized filename-level error and no raw test logs in the acceptance artifact. Other existing CI lanes retain their independent checks.

## Known limitations

- **#554:** Consent and classification policy tests pass only at Dart contract level; physical macOS permission/focus checks and privacy sign-off remain manual.
- **#555:** Schema round-trip and rejection tests exist; version-migration policy must be reviewed.
- **#556:** Proactive production vision remains OFF. Dart OCR-gate tests do not prove safe actual macOS capture or exclusion of sensitive background windows. Native work/physical validation are outstanding even if the issue is already closed.
- **#558:** Retention purge is unwired groundwork. Encrypted ActivityStore and Settings retention UI are incomplete.
- **#563:** A local-only Routine generation plan exists; no generator/validated model boundary is implemented.
- **#608:** Seeded Routine **pack import** tests are not Workflow DSL tests; the DSL and execution barrier remain unimplemented.
