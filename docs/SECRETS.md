# Secrets handling (#160)

This repo publishes public artifacts, so the rule is simple: **no secrets
in the repo, ever.** Anything sensitive lives in GitHub's own stores.

## Where secrets live

| Kind | Where | Notes |
|---|---|---|
| CI/release secrets | GitHub **Secrets** (repo or org) | Never echoed; referenced as `${{ secrets.NAME }}` |
| Release signing keys | The protected **`release` environment** | The release workflow's `build` and `publish` jobs run inside it, so environment protection rules (required reviewers) gate their use |
| Developer machine secrets | macOS Keychain / libsecret | The app itself uses `flutter_secure_storage` |

## Automated guards (CI)

- **gitleaks** scans the full git history on every push/PR (security job).
- **Native pattern scan** (`.github/scripts/scan-native-secrets.sh`) scans
  Swift/Kotlin/Java/C++/plist/gradle sources for hardcoded keys, tokens
  and private-key headers and fails the security job on any hit.
- **OSV scanner** (pinned by version + SHA-256) scans `pubspec.lock` for
  known vulnerabilities, plus a weekly scheduled re-scan of the unchanged
  lockfile so new advisories are noticed.
- **Pinned actions** job fails if any third-party action is referenced by
  a movable tag instead of a full commit SHA.

## Repo settings to verify (one-time, GitHub UI)

These can't be set from a workflow file; check them once under
**Settings → Code security and analysis**:

1. **Secret scanning** - enabled (free for public repos).
2. **Push protection** - enabled, so a commit containing a recognized
   secret is rejected at push time, before it ever reaches CI.
3. **Dependabot alerts + security updates** - enabled.

And under **Settings → Environments → release**: add a **required
reviewer** so tag-driven releases that use signing secrets need a human
approval before they run.

## What never goes into CI

No model API keys (Ollama is local) and no phone-pairing keys are ever
stored in CI secrets or workflow files. Pairing keys live on the devices
in `flutter_secure_storage`; CI never needs them. If a workflow asks for
one, the workflow is wrong.

## If a secret ever lands in history

Rotate it first (the old value is compromised the moment it is pushed),
then scrub history (`git filter-repo` or GitHub's guide) and force-push.
Scrubbing without rotating is not remediation.
