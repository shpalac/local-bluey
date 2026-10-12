# Contributor test handbook (BLU-078 / #636)

This guide describes **reproducible** test commands. Hosted CI does not prove physical-device permission, pairing, or native behavior. Never attach credentials, screen recordings containing personal data, microphone recordings, tokens, or unredacted logs.

## Requirements

- Clone the repository and install the Flutter SDK version pinned in `.flutter-version`; use a compatible Dart SDK from that Flutter distribution.
- Run `flutter doctor -v` to identify missing local prerequisites.
- Install platform toolchains only for the platforms you intend to test: Xcode and CocoaPods on macOS for Apple builds; Android SDK/emulator for Android; Linux desktop dependencies for Linux.
- From repository root, run `flutter pub get --enforce-lockfile`. Do not regenerate `pubspec.lock` while merely running tests.

## Local fast lane (all supported development hosts)

```sh
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
python3 -m unittest discover -s tool -p test_acceptance_criteria.py
python3 tool/acceptance_criteria.py --run-tests --out-dir build/acceptance
```

The last command executes named issue acceptance tests and writes sanitized summaries. An automated pass **does not** satisfy criteria classified as `manual` or `gap`. Investigate any failure rather than editing an acceptance manifest to disguise it.

## Widget, unit, integration and golden tests

```sh
flutter test test/support_matrix_test.dart
flutter test test/e2e_phone_host_test.dart
flutter test test/screenshots
```

To intentionally update screenshot baselines after reviewing a design change:

```sh
flutter test --update-goldens test/screenshots
git diff -- test/screenshots/goldens
```

Review changed PNGs against the approved visual reference, both light/dark variants and applicable RTL states. Never approve a visual regression merely to turn CI green. Golden output can depend on fonts, Flutter version and renderer; use the pinned toolchain and CI environment.

## Platform builds and native checks

```sh
flutter build apk --debug
flutter build ios --no-codesign
flutter build macos
flutter build linux
```

Run each build **only on a supported host** with its required SDKs. iOS/macOS builds require macOS/Xcode; Linux desktop builds require Linux desktop toolchains. Android emulator coverage is not proof of physical-device permission behavior. Windows host control is not a supported capability; do not claim it is verified by a cross-platform Dart test.

Physical Mac, iPhone and Android permission, microphone, Bonjour, accessibility, emergency-stop and offline/reconnect checks must follow [real-device validation](REAL_DEVICE_VALIDATION.md), with reviewer, OS versions, sanitized evidence and explicit pass/fail/not-run records. CI cannot replace these steps.

## CI and acceptance evidence

The pull-request workflow `.github/workflows/ci.yml` runs static analysis, tests, builds, platform fixtures and `acceptance-evidence`. The acceptance runner reads `docs/acceptance/criteria.json` and reports automated/manual/gap status. For issue-specific acceptance, add a bounded `docs/acceptance/issue-<number>.json` with exact test file and test name references; keep manual gaps explicit. CI uploads sanitized reports without raw test stdout. Consult the failing job log, not only the overall workflow status.

## Failure triage and rollback

1. Verify the pinned Flutter SDK and `flutter doctor -v`, then retry the failing command locally.
2. If `dart format --set-exit-if-changed` fails, run `dart format lib test` and commit only intended formatting.
3. If a golden fails, inspect the pixel diff and design requirements before regenerating any baseline.
4. If a native build cannot run on the current host, record it as **not run** and use a suitable runner/device.
5. If a permission, privacy or safety fixture fails, fail closed and do not suppress the test or relax SafetyGate.
6. Revert the offending documentation/test change through a normal PR if necessary; never remove required checks to bypass branch protection.

**Privacy/security impact:** Documentation and acceptance metadata only. No runtime permissions, egress, data retention or SafetyGate behavior is changed.
