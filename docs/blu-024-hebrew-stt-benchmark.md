# BLU-024 Hebrew STT benchmark

## Scope and baseline

The production STT contract remains `lib/services/stt.dart`. The existing
real-device benchmark is `tools/stt_bench/run_bench.sh` and its scorer is
`tools/stt_bench/wer.py`. This addition provides deterministic offline text
baseline comparison at `tools/stt_bench/hebrew_baseline.py`; it does not alter
routing, permissions, application UI, stored user data, or SafetyGate actions.
BLU-021's independent synthetic trace harness is not required to score text.

Run without a model or audio:

```sh
python3 -m unittest discover -s tools/stt_bench -p test_hebrew_baseline.py
python3 tools/stt_bench/hebrew_baseline.py path/to/consented-cases.csv
```

CSV columns: `backend,clip,state,reference,hypothesis,latency_ms`.
State is one of `success`, `invalid_input`, `offline`, `timeout`,
`permission_denied`, `cancelled`, `restart`. Success needs a transcript
and nonnegative finite latency. Failures cannot supply a transcript.
Duplicated clips and invalid states fail closed. Incomplete backends or
different clip identities cannot be ranked. Empty reference denominators
produce null accuracy, never a misleading 0% error.

Normalization uses Unicode NFKC, case folding, Hebrew cantillation/niqqud
removal and punctuation-to-space, with whitespace collapsed. WER and CER
use Levenshtein edit distance; aggregate errors are divided by aggregate
reference length, not averaged across clips. p50 is the median successful
latency of a complete evaluation set.

## Real-device protocol (manual and pending)

Use representative *consented* Hebrew recordings in a local directory outside
the repository: short commands, Hebrew-English code switching, accented
speech, background noise, silence and the application's AAC/m4a capture path.
Record device/OS, RAM, microphone, model checksum, app/whisper version, clip
identities and duration, power mode, cold vs warm load, concurrency and
whether Ollama is resident. Run both backends on identical clips and repeat
measurements; capture WER/CER, p50/p95 release-to-final latency, RSS, failures,
and false transcription on silence. See `tools/stt_bench/README.md` for
the existing model runner and `REPORT_TEMPLATE.md` for reporting.

Do not put audio, identifiers, device secrets, transcripts of private speech,
or model files in commits, CI logs or artifacts. Text-only synthetic examples
in tests are not a real acoustic accuracy claim. Make no model downloads or
cloud calls in CI. Consent is required before collecting real speech.
Verify disconnected-network behavior, denied microphone, timeout, cancellation,
app restart, rollback, RTL VoiceOver/status affordances and no unexpected egress
on a physical Mac. Record approvals and redacted evidence privately.

## Architecture, failure modes and rollback

The comparator is a read-only offline developer tool, not a user-facing feature:
no UI state, feature flag, secure storage, network API or ActionLog is invoked.
Existing STT privacy gate remains untouched. Failures are explicit and
non-comparable, not silently dropped. Stop a run by terminating the local
process; restart means initiating a new comparison from clean inputs.
Rollback is deletion/reversion of the added offline tool and CI; production
behavior requires no migration. BLU-024 cannot be considered hardware
verified until a human reviews consent, privacy and measurement evidence.
