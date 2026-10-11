# CI improvements

Implement the CI review approved by the repository owner.

1. Add a conservative git-diff classifier and tests for documentation, Dart,
   native, dependency, CI tooling, deletion and unknown-file changes. Preserve
   existing check names and reject unexpected skipped/failed/cancelled jobs.
2. Enable JSON test reporting with accurate per-test durations, failures,
   skips and incomplete runs. Upload diagnostics even after failures.
3. Remove duplicate Linux unit tests; keep X11/backend validation. Run the iOS
   simulator alongside other selected lanes. Investigate failing widget tests
   without weakening assertions or automatically retrying failures.
4. Select CodeQL jobs by native/dependency changes, cancel outdated PR scans,
   retain scheduled full scans. Isolate self-hosted native validation in a
   manually dispatched main-only workflow and protected environment.
5. Build Android and Linux releases on Ubuntu, configure Java, include Linux
   artifacts, verify collected checksums and use deterministic artifact names.
6. Generate README screenshots as read-only PR artifacts. Make branch updates
   an explicit manual action with an immutable source SHA and a safe fast-forward
   push; never overwrite concurrent work.
7. Run fixture tests, workflow lint/security checks, Flutter analysis and tests.
   Open a PR with evidence and required repository configuration steps.

## Repository settings

After the new checks have run, require `ci-required` and `codeql-required` in
branch protection. Configure a protected `native-validation` environment for
main with reviewers before registering/enabling the self-hosted runner.
These administrative settings are not available through the GitHub connector.
