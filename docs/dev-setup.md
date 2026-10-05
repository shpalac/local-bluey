# Dev setup

## All platforms

1. Install Flutter **3.47.6** (CI pins this; see
   `.github/workflows/`).
2. `flutter pub get`
3. `dart analyze lib test`
4. `flutter test` (mocked; no device or network needed)
5. `dart format lib test`

## macOS (the primary target)

- Xcode command line tools, macOS 14+.
- `flutter run -d macos`
- First run asks for microphone, speech recognition, accessibility and
  screen-recording permissions - all four are needed for hold-to-talk and
  computer control.
- Real-device checklist: wake word, hold to talk, a tool call that
  confirms through the safety gate, phone pairing over Bonjour.

## iOS (the phone remote)

- Xcode + an Apple ID; open `ios/Runner.xcworkspace` for signing.
- `flutter run -d <iphone>`
- The phone discovers the Mac over Bonjour (`_googly._tcp`); both devices
  must be on the same network.

## Android / Linux

Not supported yet - tracked in issues #51-#54. The architecture keeps
host control behind an abstraction so these ports stay possible; see
docs/architecture.md.

## Flutter version

The SDK is pinned in `.flutter-version` at the repo root; CI reads it for
every job (#157). Install the same version locally (e.g. `fvm use $(cat
.flutter-version)`) and bump the file deliberately - a weekly workflow
opens an issue when a newer stable Flutter exists.

## Everyday commands

`make check` runs exactly what the CI test lane enforces (format,
analyze, tests); `make coverage-check` adds the coverage floors, and
`make build-<platform>` wraps each build (#158). Shell scripts are
shellcheck-clean and CI enforces it.

## Local configuration and hooks

Copy `.env.example` to `.env` for local-only overrides. An opt-in
pre-commit hook (format + analyze + gitleaks) lives in
`.githooks/pre-commit`: `git config core.hooksPath .githooks`.

## Dev container

`.devcontainer/` opens a pinned-Flutter container with the Linux build
dependencies and xvfb for the Linux/Android lanes (#158). macOS/iOS
builds still need a Mac. The legacy `scripts/build-mac.sh` builds the
retired Swift-package app - kept for reference only.
