# Contributing to Bluey

Thanks for helping. This file covers the dev loop; architecture lives in
[docs/architecture.md](docs/architecture.md), platform setup in
[docs/dev-setup.md](docs/dev-setup.md).

## Setup

- Flutter **3.47.6** (the exact version CI pins; other versions may analyze
  differently).
- `flutter pub get`, then `dart analyze lib test` and `flutter test` must
  both be clean before you push. CI runs the same two commands plus a
  format check (`dart format lib test` - run it, don't eyeball it).

## Issue-driven delivery

Treat every issue as a task with complete, numbered GitHub-hosted-runner-verifiable acceptance criteria and a separate test plan for each criterion. Start with [AGENTS.md](AGENTS.md); no physical-device or human approval acceptance conditions. See [issue task lifecycle](docs/acceptance/TASK_LIFECYCLE.md) for temporary issue acceptance manifests and permanent integration-test promotion. Use standalone `Refs #n` throughout implementation, and standalone `AutoClose #n` only for complete, exclusively automated acceptance evidence. Never use GitHub-native `Closes #n`, `Fixes #n`, or `Resolves #n`: they bypass the verified post-main-CI closer.

## Branches and PRs

- Branch per issue or per tight cluster: `fix/<issue>-short-name`,
  `docs/<issue>-short-name`.
- PR body lists what changed and why, with a standalone `Refs #n` for each issue. Add `AutoClose #n` for a finished issue only after its named acceptance tests and manifest are complete.
- Keep PRs small enough to review in one sitting; stack dependent PRs and
  say so in the body.

## Tests

- Every fix lands with a failing-first test when the bug is testable.
- Host-control is faked in tests (`test/` has the fakes); nothing in the
  unit suite may touch the real screen, clipboard, microphone or network.
  Real-device checks live in the native-validation lane (macOS only) and in
  the manual checklist in docs/dev-setup.md.
- Widget tests: platform channels (secure storage, path_provider,
  path provider) have no implementation under flutter_test - either mock
  the channel or use the debug seams the services expose
  (`PrivacyGuard.debugLocalOnlyOverride`,
  `SettingsStore.debugSecureStorage`). Give real async work a
  `tester.runAsync` window; `pumpAndSettle` times out on loading spinners.

## Security

- Do not open public issues for vulnerabilities - email the maintainer
  (see the README contact) instead.
- Anything that moves data off the device goes through `PrivacyGuard` and
  is recorded by `EgressMonitor`; keep it that way and link the privacy
  issues (#58, #120-#122) in your PR.

## Style

- English in code, docs, commit messages and PR text.
- `dart format` output is canonical; the analyzer's warnings fail CI.
