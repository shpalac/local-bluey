#!/usr/bin/env bash
# Fails when a workflow references a third-party action by a movable tag
# instead of a full-length commit SHA (#81, #143). Matches both the
# `- uses:` list form and the bare `uses:` form; local (./) and docker://
# actions are exempt. Usage: check-pinned-actions.sh [workflows-dir]
set -euo pipefail
dir="${1:-.github/workflows}"
bad=$(grep -rhoE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*[^@[:space:]#]+@[^[:space:]#]+' "$dir" \
  | grep -vE 'uses:[[:space:]]*(\./|docker://)' \
  | grep -vE '@[0-9a-f]{40}([[:space:]#]|$)' || true)
if [ -n "$bad" ]; then
  echo "Unpinned actions found:"
  echo "$bad"
  exit 1
fi
echo "All actions pinned by SHA."
