# BLU-037 fast PR gate reproducibility

`test/pr_fast_ci_gate_repro_test.dart` executes the existing
`tool/test_ci_gate.py` negative-path fixture suite in the normal Dart test
runner using the local Python interpreter. Cases include required-lane
failure, cancelled/missing status, detector failure, invalid impact plans,
unexpected unselected-job failure and valid docs-only routing.

This is fail-closed **logic** evidence, not proof that repository branch
protection requires every relevant check. Administrators must verify
branch-protection rules against the `build` aggregate, Fast CI, security and
platform checks. No workflow permissions, secrets, runners or test scripts
are changed by this slice.

Reproduce on a standard hosted runner:

```sh
python3 -m unittest discover -s tool -p 'test_ci_gate.py'
flutter test test/pr_fast_ci_gate_repro_test.dart
```

The wrapper asserts an exit code only and does not publish child stdout,
secrets, tokens or raw fixtures as artifacts. Failing fixtures are visible
through the committed Python test suite. Rollback removes the additive
test and this documentation; no runtime behavior changes.
