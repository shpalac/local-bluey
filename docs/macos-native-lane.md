# BLU-038 macOS native build lane

The GitHub-hosted `macos-latest` pull-request lane builds the Flutter macOS
application and runs `RunnerTests` via Xcode after the build. The XCTest smoke
checks that the hosted Runner app bundle provides an executable. It does not
request Accessibility or Screen Recording access or capture any screenshots.

## Reproduce on macOS

Use Xcode and the Flutter SDK version in `.flutter-version`:

```sh
flutter pub get --enforce-lockfile
flutter test test/macos_build_lane_manifest_test.dart test/macos_native_xctest_lane_test.dart
flutter build macos --debug
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -only-testing:RunnerTests CODE_SIGNING_ALLOWED=NO -quiet
```

Failure is reported as a nonzero job status. Check the Xcode test target and
the Actions step output for diagnostic errors. No screenshot or test-result
artifact is uploaded by this lane. Dependency setup may contact package
registries; this smoke adds no runtime network calls or permissions. Real TCC
validation and cross-platform compatibility remain manual.

Rollback: revert this follow-up commit. Preserve the original workflow,
test target and all other files and branches.
