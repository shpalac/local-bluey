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

## Summarizing samples (#617)

`dart tool/perf_summary.dart <perf.jsonl>` prints `stage,count,p50_ms,p95_ms`
(nearest-rank percentiles) from the file PerfMonitor writes. Invalid lines
fail with exit 2 and the line number only. It reads latency and nothing else:
CPU, RAM, disk and cold-start baselines are not measured by anything in this
repository yet, and no real-device numbers are recorded here. Compare a new
summary against the table above by hand; this tool does not enforce targets.
