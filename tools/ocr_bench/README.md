# OCR bench (#213)

Measures Hebrew/English OCR accuracy of the app's `ScreenReader.recognize`
on a fixed sample: RTL Hebrew, mixed-direction lines, numbers, dates.

Run on an Apple Silicon Mac from the repo root:

    tools/ocr_bench/run_bench.sh

It compiles a tiny runner against the real `ScreenReader.swift`, renders
each fixture string to an image, runs OCR, and writes `REPORT.md` with
word-level accuracy per fixture and overall.

Fixtures live in `fixtures.json` - add a line there to grow the sample.
