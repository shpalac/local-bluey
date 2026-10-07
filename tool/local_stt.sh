#!/usr/bin/env bash
# Local speech-to-text for Bluey (#124).
#
# Bluey's HttpSttProvider speaks the OpenAI contract: it POSTs multipart to
# {base}/audio/transcriptions and reads {"text": ...} (lib/services/stt.dart).
# whisper.cpp's server only exposes POST /inference, so tool/stt_shim.py sits
# in front and forwards one to the other. Nothing leaves the machine, which
# matters because Bluey's local-only mode refuses a non-loopback endpoint.
#
# One-time setup (Metal build + ~150MB model):
#   tool/local_stt.sh setup
# Then, per session:
#   tool/local_stt.sh start
#   tool/local_stt.sh endpoint     # print what to paste into Settings
#   tool/local_stt.sh check        # transcribe a generated fixture
#   tool/local_stt.sh stop
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="${STT_ROOT:-$HOME/stt_bench}"
WHISPER="$ROOT/whisper.cpp"
MODEL="${STT_MODEL:-$WHISPER/models/ggml-tiny.en.bin}"
BIN="$WHISPER/build/bin/whisper-server"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"
UPSTREAM_PORT="${STT_UPSTREAM_PORT:-8099}"
SHIM_PORT="${STT_SHIM_PORT:-8098}"
RUN_DIR="$ROOT/run"

setup() {
  mkdir -p "$ROOT"
  if [ ! -d "$WHISPER" ]; then
    git clone --depth 1 https://github.com/ggml-org/whisper.cpp "$WHISPER"
  fi
  # The server target lives under examples/, so examples must stay enabled.
  ( cd "$WHISPER" \
    && cmake -B build -DWHISPER_METAL=ON -DWHISPER_BUILD_EXAMPLES=ON \
    && cmake --build build -j --config Release --target whisper-server )
  if [ ! -f "$MODEL" ]; then
    mkdir -p "$(dirname "$MODEL")"
    curl -L -o "$MODEL" "$MODEL_URL"
  fi
  echo "ready: $BIN"
}

start() {
  [ -x "$BIN" ] || { echo "run: tool/local_stt.sh setup" >&2; exit 1; }
  [ -f "$MODEL" ] || { echo "missing model $MODEL - run setup" >&2; exit 1; }
  mkdir -p "$RUN_DIR"
  if ! curl -s -m 2 -o /dev/null "http://127.0.0.1:$UPSTREAM_PORT/"; then
    nohup "$BIN" -m "$MODEL" --host 127.0.0.1 --port "$UPSTREAM_PORT" -l en \
      > "$RUN_DIR/whisper.log" 2>&1 &
    echo $! > "$RUN_DIR/whisper.pid"
  fi
  # The model has to finish loading before it answers; poll rather than sleep.
  for _ in $(seq 1 40); do
    curl -s -m 2 -o /dev/null "http://127.0.0.1:$UPSTREAM_PORT/" && break
    sleep 0.5
  done
  if ! curl -s -m 2 -o /dev/null "http://127.0.0.1:$UPSTREAM_PORT/"; then
    echo "whisper-server did not come up - see $RUN_DIR/whisper.log" >&2; exit 1
  fi
  if ! curl -s -m 2 -o /dev/null "http://127.0.0.1:$SHIM_PORT/"; then
    nohup python3 tool/stt_shim.py "$SHIM_PORT" > "$RUN_DIR/shim.log" 2>&1 &
    echo $! > "$RUN_DIR/shim.pid"
    sleep 1
  fi
  echo "stt up: http://127.0.0.1:$SHIM_PORT/audio/transcriptions"
}

stop() {
  for n in whisper shim; do
    f="$RUN_DIR/$n.pid"
    [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null
    rm -f "$f"
  done
  echo "stopped"
}

check() {
  local wav; wav=$(mktemp -t sttcheck).wav
  # A generated fixture, so the check needs no microphone and no network.
  say -o "${wav%.wav}.aiff" "${1:-what is on my screen}" 2>/dev/null
  ffmpeg -y -loglevel error -i "${wav%.wav}.aiff" -ar 16000 -ac 1 "$wav"
  echo "endpoint: http://127.0.0.1:$SHIM_PORT/audio/transcriptions"
  curl -s -m 120 -X POST "http://127.0.0.1:$SHIM_PORT/audio/transcriptions" \
    -F "model=whisper-1" -F "file=@$wav"
  echo
  rm -f "$wav" "${wav%.wav}.aiff"
}

case "${1:-start}" in
  setup)    setup ;;
  start)    start ;;
  stop)     stop ;;
  check)    check "${2:-}" ;;
  endpoint) echo "http://127.0.0.1:$SHIM_PORT" ;;
  *) echo "usage: $0 {setup|start|stop|check|endpoint}" >&2; exit 2 ;;
esac