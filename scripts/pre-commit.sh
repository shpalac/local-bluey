#!/usr/bin/env bash
# Opt-in pre-commit hook (#158): format + analyze + secrets scan.
# Install once: git config core.hooksPath .githooks
set -euo pipefail
cd "$(dirname "$0")/.."
dart format --set-exit-if-changed lib test tool
flutter analyze
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks protect --staged --no-banner
else
  echo "gitleaks not installed - skipping secrets scan" >&2
fi
