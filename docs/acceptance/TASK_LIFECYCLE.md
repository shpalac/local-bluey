# Issue tasks: acceptance-driven CI

Every issue is a task: a scoped objective, a numbered observable acceptance
checklist, a concrete validation plan, and a definition of done. An issue is not
completed merely because a PR merges or an unrelated CI check turns green.

## Lifecycle

1. **Triage.** Create from the task, bug, or feature template. Replace all
   placeholders with testable outcomes. Number every checklist item as
   `AC-1:`, `AC-2:`, etc.; the matching manifest IDs must be
   `ac_1`, `ac_2`, etc. Specify real platform/device limits,
   negative cases (bad inputs, permission denial, offline, restart,
   cancellation) and explicit exclusions.
2. **Start work.** Reference the issue with `Refs #123` in the PR body. Add
   `docs/acceptance/temporary/issue-123.json` and real issue-only tests in
   `test/issues/issue_123_test.dart` (or a suitable existing `test/` file).
   Each automated criterion names exact file and test case, not only a path.
3. **Verify.** CI fetches live issue acceptance criteria, validates the
   manifest and runs each named temporary test on PRs. A skipped, missing,
   timed-out or failing test blocks issue acceptance. General static, coverage,
   native build, security and Android integration jobs still run.
4. **Promote.** Add an end-to-end feature journey with error/regression cases
   in `integration_test/features/<feature>_test.dart`. Create a permanent
   `docs/acceptance/permanent/issue-123.json` mapping the issue to actual
   named integration tests. These run on the existing Android emulator matrix.
   Keep relevant smaller unit tests in the ordinary `test/` suite.
5. **Remove temporary evidence.** In the same change, delete the temporary
   manifest and issue-only tests that are genuinely redundant. Do not remove
   production regression tests. The gate rejects both manifests being present.
6. **Finish.** Use `Closes #123` only after the permanent mapping exists,
   automated tests pass at the exact PR head, and every remaining criterion
   is genuinely resolved. Human/device-only criteria require separate
   maintainer evidence; the gate intentionally rejects automatic closing when
   any such criterion is still declared manual or unimplemented.

Do not add a GitHub Actions YAML file per issue. The existing permanent
`acceptance-evidence` job is the lightweight dispatcher. **Temporary CI**
means temporary issue-only acceptance tests and the issue manifest, not a
permanent job in the Actions UI. The issue's named assertions disappear from
that dispatcher only when permanent tests replace them.

## Manifest example (temporary)

Create `docs/acceptance/temporary/issue-123.json`:

```json
{
  "version": 1,
  "issues": [{
    "number": 123,
    "title": "Example feature",
    "criteria": [
      {
        "id": "ac_1",
        "requirement": "A valid user action reaches the expected result",
        "type": "automated",
        "tests": [{
          "file": "test/issues/issue_123_test.dart",
          "name": "valid user action reaches expected result"
        }]
      },
      {
        "id": "ac_2",
        "requirement": "Physical macOS permission revocation works",
        "type": "manual",
        "reason": "Requires a real Mac TCC grant/revoke scenario and signed evidence"
      }
    ]
  }]
}
```

Every referenced test name must exist as a literal Dart `test` or
`testWidgets` case, and it must actually execute successfully. The
example is illustrative: do not commit it without real code and matching
tests. For the permanent manifest, change the file to a real
`integration_test/features/..._test.dart` and update the requirement to
describe the complete user journey. Keep any unresolved manual row; CI does
not turn it green by relabeling it.

## CI commands

```sh
python3 -m unittest discover -s tool -p 'test_acceptance_criteria.py'
python3 -m unittest discover -s tool -p 'test_issue_task_ci.py'
python3 tool/acceptance_criteria.py --run-tests --out-dir build/acceptance

# In GitHub Actions, PR event + repository are supplied automatically:
python3 tool/issue_task_ci.py --mode unit
# Inside the existing Android emulator action:
python3 tool/issue_task_ci.py --mode integration
```

**Existing backlog:** The 81 open issues as reviewed on 2026-10-12 have
acceptance checklists and CI plans; most do not yet have executable
issue-specific test manifests. That is **work remaining**, not proof they
have passed. The baseline `docs/acceptance/criteria.json` and older
`docs/acceptance/issue-N.json` entries remain supported for incremental
migration. Those *legacy* mappings are useful evidence for `Refs` PRs, but
do not authorize issue-closing keywords.

**Boundaries:** Android emulators verify the flows they can actually run.
macOS Screen Recording/Accessibility (TCC), physical audio behavior, real
iPhone/macOS parity, hardware pairing and production-model locality cannot
be fully certified by hosted Flutter mocks. Leave those criteria explicit,
retain issue state until separately verified, and never assert 100% coverage
from a simulation-only run. Research, security review, documentation and
native-only issues may require specific non-Flutter checks or human sign-off
rather than an artificial app integration test; introduce a suitable audited
verification contract for those before trying to auto-close them.

## Security

The checker uses read-only GitHub API access to inspect the actual issue
body and runs only checked-in, path-restricted test files. It never downloads
third-party PR scripts from issue text, never runs arbitrary commands from
GitHub issue bodies, and strips GitHub API credentials before invoking test
processes. Reports only contain bounded file/test identifiers; manual
evidence and real-device decisions must not include secrets or PII.
