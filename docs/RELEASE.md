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

## Secrets and scanning (#160)

Verified in the repository settings on 2026-10-08: secret scanning, push
protection and Dependabot security updates are on, and the `release`
environment has a required reviewer. `release.yml` jobs that touch signing
material run in that environment; nothing else in CI sees signing secrets.

- Where secrets live: signing certificates, notary credentials and any store
  tokens are `release` environment secrets, never repository-wide secrets.
- Least privilege: workflows default to `contents: read`. A job gets
  `id-token: write`, `attestations: write` or `contents: write` only where it
  needs it (see `release.yml`).
- No model API keys, endpoints or pairing keys are ever stored in CI.
- Rotation: rotate the Apple notary app-specific password and any store
  tokens every 90 days, and immediately after a leak or a reviewer change.
  Replace the environment secret, run the release workflow on a test tag,
  then revoke the old credential. Prefer short-lived OIDC credentials where
  the target service supports them.
- Scans: CodeQL (Kotlin and Swift), gitleaks, OSV, actionlint and zizmor run
  on pull requests and weekly on a schedule.
- Not verified here: that push protection actually blocks a test secret. Do
  that once from a throwaway branch with a fake token, then delete it.
