# Changelog

Releases follow [SemVer](https://semver.org): `version: X.Y.Z+build` in
pubspec.yaml, tags `vX.Y.Z` (the release workflow fails on mismatch).
Notes are generated from merged PRs per `.github/release.yml`; this file
summarizes the highlights per release (Keep a Changelog style).

## [Unreleased]

### Added
- Linux runner and ubuntu CI lane (#149).
- CI hardening: pipefail, enforced SHA pinning, pinned+verified OSV (#142-#144).
- Coverage floors for lib/services and lib/link (#136).
