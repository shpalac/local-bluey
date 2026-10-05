#!/bin/sh
# Build whisper.cpp with Metal and download the benchmark models (#195).
# No Homebrew/Python needed for the backend itself.
set -eu
ROOT="$HOME/stt_bench"
WHISPER="$ROOT/whisper.cpp"
MODELS="$ROOT/models"
mkdir -p "$MODELS"

if [ ! -d "$WHISPER" ]; then
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp "$WHISPER"
fi
cd "$WHISPER"
git rev-parse HEAD > "$ROOT/whisper_rev.txt"
cmake -B build -DWHISPER_METAL=ON
cmake --build build -j --config Release

echo "Downloading models into $MODELS"
# Stock multilingual turbo
sh ./models/download-ggml-model.sh large-v3-turbo
cp models/ggml-large-v3-turbo.bin "$MODELS/" 2>/dev/null || true
# ivrit-ai Hebrew turbo GGML
curl -L -o "$MODELS/ggml-ivrit-turbo.bin" \
  "https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/resolve/main/ggml-model.bin" || \
  echo "ivrit-ai GGML download failed - check the exact filename on the HF repo"
echo "Done. whisper-cli at $WHISPER/build/bin/whisper-cli"
