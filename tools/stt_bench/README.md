# STT Hebrew benchmark harness (#195)

Measures Hebrew-first STT backends on macOS and produces the numbers the
#196/#197 integration needs. Runs locally on your Mac; nothing here ships
with the app. whisper.cpp + Metal is the leading candidate, WhisperKit and
MLX Whisper are the comparisons. `.en` models are never used for Hebrew.

## What you need
- macOS 14+ on Apple Silicon, Xcode CLT (`xcode-select --install`), cmake
- Python 3.10+ only for scoring (`pip install jiwer`) - scoring is
  offline; no backend needs Python
- ~8 GB free disk for models

## Quick start
```sh
./tools/stt_bench/setup_whisper_cpp.sh        # builds whisper.cpp, downloads models
./tools/stt_bench/run_bench.sh                # runs the matrix, writes results/
python3 tools/stt_bench/wer.py results/       # scores every run -> results/report.md
```
Fill `results/report.md` (template in REPORT_TEMPLATE.md) with chip, RAM,
macOS, power mode and the per-run numbers, then paste it into issue #195.

## Fixtures
`fixtures/` holds references only - never commit private voice clips.
See fixtures/README.md for public Hebrew sources, synthetic generation and
how to add your own consented recordings under `~/stt_bench_private/`.
Record via the app's own AAC/m4a capture path for at least a few clips so
the benchmark tests the real input format (#197 will decode exactly this).

## Reading the report
`wer.py` reconciles every attempt in `timings.csv` (which now records each
run's exit status) with its reference and transcript. A backend that failed
any clip is marked `INCOMPLETE - not comparable`: its WER/CER cover only the
clips it finished, its p50/p95 use successful attempts only, and failed
attempts are listed with their exit status. Rank only backends marked
`complete`. Old runs without an exit status are never treated as successes.
Offline tests: `python3 -m unittest discover -s tools/stt_bench -p test_wer.py`.

## What is measured
- Normalized Hebrew WER and CER (nfkc + nikud/punctuation strip)
- Command/slot correctness: app names, numbers, Hebrew/English switching
- Cold model load, warm release-to-final latency (p50/p95), peak RSS
- Each run is repeated with Ollama loaded (start `ollama serve` and load
  your usual model before `run_bench.sh --with-ollama`)
