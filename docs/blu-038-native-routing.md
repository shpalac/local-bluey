# BLU-038 macOS native CI path routing

`.github/workflows/macos-native-build-lane.yml` is triggered for native
macOS and iOS source changes, shared Flutter implementation, native lane
Dart tests (`test/macos*`), dependency manifest/lockfile changes and the
pinned Flutter version. This prevents modifications to the build
environment or the lane's test contract from silently skipping the native
XCTest and macOS build job.

The lane keeps GitHub-hosted macOS runners, read-only workflow token,
pinned checkout/Flutter action SHAs and
`CODE_SIGNING_ALLOWED=NO`. No raw screenshots, model downloads or
privileged secrets are introduced.

Run `flutter test test/macos_native_change_routing_test.dart` to check
routing structure. This does not establish successful native compilation;
verify the macOS CI job on the exact PR head. Real Accessibility/TCC and
physical device tests remain manual. Rollback removes only the additional
path filters; no application migration.
