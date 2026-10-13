# Incident and release rollback runbook (#637, partial)

Scope: what to do when a tagged release, a CI workflow, or a leaked secret goes wrong. It is grounded in `.github/workflows/release.yml`, `docs/RELEASE.md` and `docs/SECRETS.md` as they exist today. It does not describe signing or notarization (not in place, see #39), store submission, user notification, telemetry or any server, because none of those exist in this repository.

**Approval rule.** Steps that change external services (deleting a GitHub release or tag, rotating or revoking credentials, changing repository settings, contacting users) are owner actions. Do them only with the repository owner's explicit go-ahead. Repository-local steps (reverting a commit in a PR, adding a test) need no extra approval but still go through review.

## 1. Bad release (tag already pushed)

1. Stop the bleeding in the repository first: open a PR that reverts the offending change on `main`. Do not force-push `main` and do not bypass required checks.
2. Check the release run: `gh run list --workflow Release --limit 5`. The pipeline is tag-driven (`v*.*.*`); the tag must equal the pubspec version or it fails early.
3. If the release is public and harmful, the owner decides whether to mark it as a pre-release or delete the GitHub release and tag. Deleting a published artifact is irreversible for anyone who already downloaded it, so say so in the release notes of the fix.
4. Ship the fix as a new version. Bump `pubspec.yaml` version and build number (`+N`) and push a new tag. Never reuse or move an existing tag.
5. Verify the new artifacts: `gh attestation verify <artifact> --repo shpalac/local-bluey` and compare the SHA256 sidecar.

## 2. Leaked secret

1. Treat it as compromised immediately. Rotate first, clean history second.
2. Rotation is an owner action: replace the secret in the `release` environment (or repository secrets), run the release workflow on a test tag, then revoke the old credential. Notary and store tokens follow the 90-day rotation rule in `docs/RELEASE.md`.
3. gitleaks scans history on every push and PR (see `docs/SECRETS.md`). A hit in a PR blocks merge; do not allowlist a real secret.
4. Use obviously fake strings in tests and docs so the scan stays meaningful.

## 3. Broken CI or required check

1. Find the failing job from the PR checks. Required checks are test, security, linux, static, build-ios, build-macos and android.
2. Fix the cause. Do not skip checks, delete tests, use admin bypass or add self-hosted runners. If a check is flaky, follow `docs/FLAKE_POLICY_PLAN.md`.
3. Record what failed and the reproduction command in the PR body.

## 4. Privacy-affecting defect

1. If data may have been captured, stored or sent outside the documented boundaries, stop work on features that touch that path and open an issue with sanitized evidence (no personal data, no raw logs).
2. The retention and erasure policy is still an open owner decision (#351). Do not invent a policy or promise deletion behavior in an incident write-up.
3. A fix PR needs a regression test that fails on the old behavior.

## What this runbook does not cover

Signing and notarization failures, App Store or TestFlight rejection, user-facing notices, on-call rotation, SLAs and device-only (TCC, permission, hardware) incidents. Those need owner decisions or real-device evidence and are not claimed here.
