#!/usr/bin/env bash
# Regenerates every screenshot golden and refreshes docs/screenshots (#180).
# Run twice -> identical files (pinned size, DPR, theme, font, locale).
set -euo pipefail
cd "$(dirname "$0")/.."
"${FLUTTER:-flutter}" test test/screenshots --update-goldens
mkdir -p docs/screenshots
cp test/screenshots/goldens/*.png docs/screenshots/
echo "Updated docs/screenshots: $(ls docs/screenshots | wc -l) images"
