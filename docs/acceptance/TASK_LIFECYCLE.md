# Issue tasks: acceptance-driven CI

Every issue is a task: a scoped objective, a numbered observable acceptance
checklist, a concrete validation plan, and a definition of done. An issue is not
completed merely because a PR merges or an unrelated CI check turns green.

## Lifecycle

New or edited issues are checked by `.github/workflows/issue-task-hygiene.yml`.
If an acceptance checklist or CI plan is missing, the check fails and adds
one remediation comment; it never invents the missing requirements.

1. **Triage.** Create from the task, bug, or feature template. Replace all
   placeholders with testable outcomes. Number every checklist item as
   `AC-1:`, `AC-2:`, etc.; the matching manifest IDs must be
   `ac_1`, `ac_2`, etc. Specify real platform/device limits,
   negative cases (bad inputs, permission denial, offline, restart,
   cancellation) and explicit exclusions.
2. **Start work.** Reference work with a standalone `Refs #123` line in the PR body. A merged `Refs` PR closes the issue only if **every** numbered criterion is proven; incremental PRs leave it open. Add a separate `AutoClose #123` line when the completed PR should also opt in to automatic squash merge after green PR CI. Add
   `docs/acceptance/temporary/issue-123.json` and real issue-only tests in
   `test/issues/issue_123_test.dart` (or a suitable existing `test/` file).
   Each automated criterion names exact file and test case, not only a path.
3. **Verify.** CI fetches live issue acceptance criteria, validates the
   manifest and runs each named temporary test on PRs. A skipped, missing,
   timed-out or failing test blocks issue acceptance. General static, coverage,
   native build, security and Android integration jobs still run.
4. **Promote when useful.** Add an end-to-end feature journey with error/regression cases
   in `integration_test/features/<feature>_test.dart`. Create a permanent
   `docs/acceptance/permanent/issue-123.json` mapping the issue to actual
   named integration tests. These run on the existing Android emulator matrix.
   Keep relevant smaller unit tests in the ordinary `test/` suite.
5. **Remove redundant temporary evidence after promotion.** In the same change, delete the temporary
   manifest and issue-only tests that are genuinely redundant. Do not remove
   production regression tests. The gate rejects both manifests being present.
6. **Finish automatically.** The issue-scoped CI requires exact test names,
   successful unskipped execution and an exact match between all live issue
   AC identifiers and the temporary **or** permanent manifest. Any `manual`
   or `gap` criterion, legacy manifest, missing test or skipped result blocks
   closure. For `AutoClose` PRs the trusted workflow enables GitHub squash
   auto-merge only after CI succeeds at the exact PR head. After any linked
   `Refs` or `AutoClose` PR merges, a separate trusted workflow waits for
   successful CI on the merge commit in `main`, rechecks the live issue and
   manifest, and closes the issue **only** if every criterion is complete.
   GitHub-native `Closes #123` closes **immediately on merge** and bypasses
   this post-main-CI delay: use `AutoClose #123` for this automation.

Do not add a GitHub Actions YAML file per issue. The existing permanent
`acceptance-evidence` job is the lightweight dispatcher. **Temporary CI**
means temporary issue-only acceptance tests and the issue manifest, not a
permanent job in the Actions UI. The issue's named assertions disappear from
that dispatcher only when permanent tests replace them, or when the targeted feature suite continues to
run under the normal regression CI.

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
do not authorize automated issue closure.

**Boundaries:** Android emulators verify the flows they can actually run.
macOS Screen Recording/Accessibility (TCC), physical audio behavior, real
iPhone/macOS parity, hardware pairing and production-model locality cannot
be fully certified by hosted Flutter mocks. Leave those criteria explicit,
retain issue state until separately verified, and never assert 100% coverage
from a simulation-only run. Research, security review, documentation and
native-only issues may require specific non-Flutter checks or human sign-off
rather than an artificial app integration test; introduce a suitable audited
verification contract for those before trying to auto-close them.

## Automatic merge and closure contract

- Existing `Refs` PRs are eligible for **post-merge issue closure** when all
  acceptance criteria are satisfied; they never enable automatic PR merging.
  `AutoClose #N` remains the explicit opt-in for automatic squash merge and
  strict pre-merge acceptance validation. Incremental `Refs` PRs leave their
  issues open without failing post-merge issue automation.
- Both workflows execute trusted `main` code only. Neither checks out or
  executes a contributor branch with a privileged token.
- The PR CI must succeed at the exact head SHA, including issue-specific
  test evidence and the required aggregate gate. Main CI must succeed at the
  exact merged SHA before the issue is closed. Documentation-only merges also
  trigger main CI.
- Permanent integration tests are recommended for real user journeys, but
  not mandatory for narrowly scoped pure-Dart or documentation issues with
  complete temporary automated evidence. Real-device/TCC criteria remain
  open until a valid automated verification exists; no CI mock is a substitute.
- Branch protection should require the repository `build` aggregate and
  relevant platform/security checks. Auto-merge obeys GitHub protection rules;
  absent rules, a green CI workflow can trigger immediate merge.

## Security

The checker uses read-only GitHub API access to inspect the actual issue
body and runs only checked-in, path-restricted test files. It never downloads
third-party PR scripts from issue text, never runs arbitrary commands from
GitHub issue bodies, and strips GitHub API credentials before invoking test
processes. Reports only contain bounded file/test identifiers; manual
evidence and real-device decisions must not include secrets or PII.
