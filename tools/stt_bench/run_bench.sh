#!/bin/sh
# Run every enabled model over the fixtures and time each pass (#195).
# Usage: run_bench.sh [--fixtures DIR] [--with-ollama] [--backend NAME] [--clip FILENAME]
set -eu
ROOT="${STT_ROOT:-$HOME/stt_bench}"
WHISPER="$ROOT/whisper.cpp"
MODELS="$ROOT/models"
FIXTURES="tools/stt_bench/fixtures"
WITH_OLLAMA=0
BACKENDS=""
CLIPS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fixtures) FIXTURES="$2"; shift 2;;
    --backend) BACKENDS="$BACKENDS $2"; shift 2;;
    --clip) CLIPS="$CLIPS $2"; shift 2;;
    --with-ollama) WITH_OLLAMA=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
mkdir -p "$ROOT/results"
OUT=$(mktemp -d "$ROOT/results/$(date +%Y%m%d-%H%M%S)-XXXXXX")
# Validate all selected inputs before starting any inference or publishing results.
python3 "$(dirname "$0")/validate_inputs.py" "$ROOT" "$FIXTURES" "$OUT" "$BACKENDS" "$CLIPS"
CLI="$WHISPER/build/bin/whisper-cli"
[ -x "$CLI" ] || { echo "run setup_whisper_cpp.sh first" >&2; exit 1; }

run_model() {
  name="$1"; model="$2"; lang="$3"
  echo "== $name =="
  while IFS= read -r base; do
    clip="$FIXTURES/$base"
    base="$(basename "$clip")"
    t0=$(python3 -c 'import time; print(int(time.time()*1000))')
    # Record the real exit status instead of hiding it: the scorer must be
    # able to tell a failed attempt from a successful one (#270).
    rc=0
    # STT_TIME lets tests run where /usr/bin/time has no -l (non-macOS).
    ${STT_TIME:-/usr/bin/time -l} "$CLI" -m "$model" -l "$lang" -nt -otxt \
      -of "$OUT/$name--$base" -f "$clip" 2> "$OUT/$name--$base.time" || rc=$?
    t1=$(python3 -c 'import time; print(int(time.time()*1000))')
    peak=$(awk '/maximum resident set size/ {print $1}' "$OUT/$name--$base.time")
    echo "$name,$base,$((t1-t0)),$peak,$rc" >> "$OUT/timings.csv"
  done < "$OUT/clips.txt"
}

echo "backend,clip,latency_ms,peak_rss_bytes,exit_status" > "$OUT/timings.csv"
while IFS= read -r backend; do
  case "$backend" in
    whispercpp-turbo) run_model "$backend" "$MODELS/ggml-large-v3-turbo.bin" he;;
    whispercpp-ivrit) run_model "$backend" "$MODELS/ggml-ivrit-turbo.bin" he;;
    whispercpp-v3) run_model "$backend" "$WHISPER/models/ggml-large-v3.bin" he;;
  esac
done < "$OUT/backends.txt"
[ $WITH_OLLAMA -eq 1 ] && echo "Ollama should be serving; results tagged" \
  && touch "$OUT/with-ollama"
echo "Wrote $OUT - score with: python3 tools/stt_bench/wer.py $OUT $FIXTURES/refs.csv"
