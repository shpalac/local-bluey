#!/bin/sh
# Builds and runs the Hebrew/English OCR bench on a Mac (#213).
# Output: tools/ocr_bench/REPORT.md
set -e
cd "$(dirname "$0")"
BIN=/tmp/ocr_bench
swiftc -O main.swift ../../macos/Runner/ScreenReader.swift \
  ../../macos/Runner/ControlsReader.swift ../../macos/Runner/ComputerControl.swift \
  -framework AppKit -framework Vision -framework ScreenCaptureKit \
  -framework ApplicationServices -framework Carbon \
  -o "$BIN"
"$BIN" fixtures.json > results.jsonl
python3 score.py results.jsonl REPORT.md
