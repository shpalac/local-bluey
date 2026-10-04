# Performance baselines (#37)

Stages measured by PerfMonitor (samples in perf.jsonl on the Mac):

| Stage | What | Target baseline |
|---|---|---|
| idle | App open, face animating | < 5% CPU, no network |
| listening.transcription | hold-to-talk m4a -> text | < 2s for a 5s utterance |
| thinking.brain | full brain roundtrip | < 4s local model |
| acting.tool.* | each tool execution | < 1s (look_at_screen < 2s) |

Re-measure after each model or OS change; regressions > 50% vs the
last baseline are a bug, not a vibe.
