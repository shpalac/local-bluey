# Benchmark fixtures (#195)

Never commit private voice samples. This folder keeps reference manifests;
audio stays local.

## Clips you need (~30)
1. **Short Hebrew commands** (10-15): 2-8 seconds each, e.g. timers,
   openings, questions. Manually transcribed - put transcripts in
   `refs.csv` as `filename,transcript`.
2. **Hebrew/English code switching** (5): app names, "פתח את WhatsApp",
   numbers, emails.
3. **Accented Hebrew** (3-5): non-native speakers if consented.
4. **Noisy clips** (3): street/cafe background.
5. **Silence / near-silence** (2): must return empty, not hallucination.
6. **App-path capture** (3+): recorded through the app's own AAC/m4a
   capture, 16 kHz - this is the format #197 decodes.

## Public / synthetic sources
- ivrit-ai evaluation sets and samples: https://huggingface.co/ivrit-ai
- Synthetic silence/noise: `sox -n -r 16000 silence.wav trim 0.0 3.0`
- TTS-generated commands are acceptable for smoke tests, not for the
  published WER numbers.

## Layout
- Public/synthetic clips may live here with a `refs.csv`.
- Private clips: `~/stt_bench_private/` with the same `refs.csv` format;
  `run_bench.sh --fixtures ~/stt_bench_private` picks them up.
