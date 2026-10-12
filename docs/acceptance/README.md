# Issue acceptance evidence (BLU backlog)

For the required task lifecycle, issue-linked temporary CI and promotion to permanent end-to-end tests, see [TASK_LIFECYCLE.md](TASK_LIFECYCLE.md). The existing manifest below remains a legacy baseline and is not evidence that every open issue has passed.

This is **bounded verification**, not automatic sign-off. It covers #554, #555, #556, #558, #563 and #608 as of its introduction; extend the manifest when new implementation work lands. Sources: those issues' acceptance criteria and merged PRs #665, #666, #668, #678, #663 and #683. The issue's actual acceptance criteria take precedence if they change.

## What CI proves

- `.github/workflows/ci.yml` runs `acceptance-evidence` on PRs and `main`. It checks **named test cases actually exist**, then runs their entire test files with Flutter. Missing/renamed tests, a bad manifest, timed-out tests and failed suites fail CI. Green means only the covered *automated* behavior was exercised.
- The existing required `build` aggregate depends on `acceptance-evidence`, so a failing automated evidence gate blocks that required check as well. This does not require changing branch-protection settings.
- The check emits `acceptance.md` and `acceptance.json` with `passed`, `failed`, `manual_required`, or `not_implemented`. Artifacts include only bounded filenames, criterion IDs and rationale. Raw test stdout and fixture secrets are not included.
- A `manual_required` or `not_implemented` row is never counted as `passed`, regardless of neighboring suite results. Hardware security, OS permissions, model locality and human review require real evidence.
- Green CI **does not close issues, grant privacy/security approval, enable vision capture or authorize persistent storage**.

## Review and completion procedure

1. Compare each issue's current acceptance criteria with `criteria.json`. Update this manifest when implementation changes; do not remove unmet criteria to make CI green.
2. Add an actual `test/..._test.dart` path and exact test name for each newly automated criterion. The validator fails if the test is removed or renamed. Run the entire file to avoid hiding neighboring regressions.
3. Change a `gap` to `automated` **only after the production integration exists** and a regression test exercises it. Keep `manual` until a reviewer records build/device/OS, actions, outcomes, commit SHA and evidence URL.
4. A maintainer must check all relevant issue criteria and required checks before closing an issue. This CI does not auto-close or pretend unimplemented features are complete.

## Local commands

```sh
python3 -m unittest discover -s tool -p 'test_acceptance_criteria.py'
python3 tool/acceptance_criteria.py --out-dir build/acceptance
flutter pub get --enforce-lockfile
python3 tool/acceptance_criteria.py --run-tests --out-dir build/acceptance
```

Without `--run-tests`, automated rows say `not_run` rather than `passed`. A failing Flutter test yields only a sanitized filename-level error and no raw test logs in the acceptance artifact. Other existing CI lanes retain their independent checks.

## Known limitations

- **#554:** Consent and classification policy tests pass only at Dart contract level; physical macOS permission/focus checks and privacy sign-off remain manual.
- **#555:** Schema round-trip and rejection tests exist; version-migration policy must be reviewed.
- **#556:** Proactive production vision remains OFF. Dart OCR-gate tests do not prove safe actual macOS capture or exclusion of sensitive background windows. Native work/physical validation are outstanding even if the issue is already closed.
- **#558:** Retention purge is unwired groundwork. Encrypted ActivityStore and Settings retention UI are incomplete.
- **#563:** A local-only Routine generation plan exists; no generator/validated model boundary is implemented.
- **#608:** Seeded Routine **pack import** tests are not Workflow DSL tests; the DSL and execution barrier remain unimplemented.
