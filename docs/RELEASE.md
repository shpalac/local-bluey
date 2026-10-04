# Release readiness (#39)

Artifacts: signed + notarized macOS app, signed iOS build (TestFlight).

## Checklist
- [ ] Apple Developer account + certificates (Developer ID Application for
      direct macOS distribution; App Store distribution profile for iOS)
- [ ] macOS: `flutter build macos --release`, codesign with hardened runtime,
      notarize via `xcrun notarytool`, staple
- [ ] Entitlements review: sandbox off today - decide sandbox vs. the
      accessibility/screen-recording permissions story before shipping
- [ ] iOS: `flutter build ipa`, upload via Xcode/Transporter, TestFlight review
- [ ] CI: add a `release` workflow building signed artifacts on tag push
      (secrets: certificates + notary credentials in GitHub secrets)
- [ ] Versioning: bump pubspec version + build number per release
- [ ] docs/VALIDATION.md pass on both devices before every tag
