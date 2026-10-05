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

## Tag-driven pipeline (#155)

Pushing `vX.Y.Z` runs `.github/workflows/release.yml`: the tag must equal
the pubspec version or the workflow fails; tests run first, then macOS /
iOS / Android build in the protected `release` environment, artifacts
get SHA256 sidecars, a CycloneDX SBOM is generated from pubspec.lock by
`tool/sbom.dart` (no external binary), provenance is attested with the
SHA-pinned attest action (`gh attestation verify`), and the release is
created with generated notes. Signing/notarization secrets go in the
`release` environment when #39 lands - the pipeline shape does not
change. Build numbers come from pubspec's `+N`; bump with the version.
