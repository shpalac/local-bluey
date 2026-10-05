#!/bin/sh
# Run every enabled model over the fixtures and time each pass (#195).
# Usage: run_bench.sh [--fixtures DIR] [--with-ollama]
set -eu
ROOT="$HOME/stt_bench"
WHISPER="$ROOT/whisper.cpp"
MODELS="$ROOT/models"
FIXTURES="tools/stt_bench/fixtures"
WITH_OLLAMA=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fixtures) FIXTURES="$2"; shift 2;;
    --with-ollama) WITH_OLLAMA=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
OUT="$ROOT/results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
CLI="$WHISPER/build/bin/whisper-cli"
[ -x "$CLI" ] || { echo "run setup_whisper_cpp.sh first" >&2; exit 1; }

run_model() {
  name="$1"; model="$2"; lang="$3"
  echo "== $name =="
  for clip in "$FIXTURES"/*.m4a "$FIXTURES"/*.wav; do
    [ -e "$clip" ] || continue
    base="$(basename "$clip")"
    t0=$(python3 -c 'import time; print(int(time.time()*1000))')
    /usr/bin/time -l "$CLI" -m "$model" -l "$lang" -nt -otxt \
      -of "$OUT/$name--$base" -f "$clip" 2> "$OUT/$name--$base.time" || true
    t1=$(python3 -c 'import time; print(int(time.time()*1000))')
    peak=$(awk '/maximum resident set size/ {print $1}' "$OUT/$name--$base.time")
    echo "$name,$base,$((t1-t0)),$peak" >> "$OUT/timings.csv"
  done
}

echo "backend,clip,latency_ms,peak_rss_bytes" > "$OUT/timings.csv"
[ -f "$MODELS/ggml-large-v3-turbo.bin" ] && \
  run_model whispercpp-turbo "$MODELS/ggml-large-v3-turbo.bin" he
[ -f "$MODELS/ggml-ivrit-turbo.bin" ] && \
  run_model whispercpp-ivrit "$MODELS/ggml-ivrit-turbo.bin" he
[ -f "$WHISPER/models/ggml-large-v3.bin" ] && \
  run_model whispercpp-v3 "$WHISPER/models/ggml-large-v3.bin" he
[ $WITH_OLLAMA -eq 1 ] && echo "Ollama should be serving; results tagged" \
  && touch "$OUT/with-ollama"
echo "Wrote $OUT - score with: python3 tools/stt_bench/wer.py $OUT $FIXTURES/refs.csv"
