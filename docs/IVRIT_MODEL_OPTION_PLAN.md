# Ivrit model option plan

Research: 2026-10-11. Refs #579. Main `3caf8a2`. Preparation only, not full #579 acceptance. No model downloaded, catalogue/default selected, downloader configured, provider/native worker activated or issue closed. Historical #198/#281 contracts are preserved below; their current live issue reads returned 404 during this audit, so current status/ownership is unverified rather than assumed from older reports.

## Answer and candidate evidence

Ivrit-ai's Hebrew Whisper large-v3-turbo has an upstream GGML artifact explicitly advertised for Whisper.cpp, so it is a candidate for later native qualification, not a drop-in installed provider. Its model card says language detection and translation degraded: explicit Hebrew is required and translation must not be advertised. Mixed-language profile selection and the default still require #195/device evidence. The existing native provider remains not-installed.

The primary GGML [artifact commit](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/commit/2130c78e4a9cb4914cc4df91a1c3031407789705) exposes the changed LFS pointer, so exact bytes and digest are source evidence rather than guesses from the rounded file listing. This is metadata inspection only, not locally verified downloaded bytes or native compatibility.

| Candidate field | Observed evidence | Remaining limitation |
| --- | --- | --- |
| Repository/variant | ivrit-ai/whisper-large-v3-turbo-ggml, ggml-model.bin. Card advertises Whisper.cpp and Vibe. | No selected Bluey worker version or actual load/inference test. |
| Artifact revision | `2130c78e4a9cb4914cc4df91a1c3031407789705`, upstream commit titled 2025.05.13. | Record source revision and backend compatibility separately. Mutable main URL is not a production pin. |
| SHA-256 | `c8090411113357097bfafc2b8e228ec1639fa7f5fe4ecb5d054ac0ccef8641b1`, published pointer/file SHA256. | Not the Xet storage hash; no local download/hash verification occurred. |
| Exact bytes | `1624555275` in the commit pointer; listing rounds to 1.62GB. | Disk artifact size is not resident memory, peak working set or Ollama headroom. |
| License | Apache-2.0 advertised on GGML listing and source model card. | Capture complete notices and derivative/backend license inventory before redistribution; a nonempty ModelAsset notice is not legal verification. |
| Language/task | Hebrew finetune, Apr 2025 training; card requires explicit Hebrew, warns degraded language detection and translation. | No measured Bluey Hebrew/code-switching accuracy or platform capability matrix. |

The CT2 [model](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ct2) is a separate faster-whisper/CTranslate2 route. Its [model.bin page](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ct2/blob/main/model.bin) publishes SHA256 `db2a2265aa012c16c7db9edda3d699c99f984efdd3f2e22a72a8ce7e9720f3a2`, not the GGML digest. CT2 also includes config/tokenizer/vocabulary/preprocessor files. Do not relabel that bundle as one GGML file or copy its digest into a whisper.cpp manifest. Exact complete CT2 bundle bytes/notices and backend adapter remain unselected.

The upstream [leaderboard](https://ivrit-ai-hebrew-transcription-leaderboard.hf.space/) describes podcast, volunteer WhatsApp, read-speech and broadcast corpora. The fetched table unexpectedly labels its single ivrit CT2 row with engine 'amazon-transcribe'. Treat the row as insufficiently attributed for a precise comparison; no WER recommendation is taken from it. Even corrected public corpus scores would not be Bluey device latency/memory/Hebrew qualification.

## Current storage/STT source, not future readiness

Complete [ModelStore](../lib/services/model_store.dart), [STT](../lib/services/stt.dart), [PCM](../lib/services/pcm_decode.dart), [registry](../lib/services/data_registry.dart), model/STT/PCM fixtures and pubspec were reviewed. [MODEL_CORE_ACCEPTANCE](MODEL_CORE_ACCEPTANCE.md) preserves the earlier original 281 bounded storage versus 198 production-manager reconciliation; its historical pending delivery labels stay historical.

ModelAsset pins caller id/revision/exact bytes/digest/format/backend/notice/language labels. It does not contain a download URL, backend revision, capability proof or runtime-memory field. ModelStore injects downloader/freeSpace; accepted format/backend sets default empty, and production has no install/acquire consumer found by the lib search outside registry clearing. Explicit install admits nonblank notice, positive bytes/lowercase64hex hash and accepted sets, stages offset transfers, checks size/hash and serializes selection commit. Do not infer production downloader or catalogue from those seams.

Short transfer is interrupted/resumable; overlong transfer wrongSize; bad hash deletes corrupt partial and does not activate. Cancel is checked as injected stream yields/finishes, not guaranteed abort of stalled I/O. Same-size changed selected bytes remain active/leased after restart because activeAsset checks metadata/existence/size, not rehash; alreadyActive likewise does not reverify. New ivrit metadata must not silently select a rehash/quarantine policy. Leases preserve old bytes across selection/remove/delete until release; logical deletion is not immediate physical erasure. Inventory excludes inactive leased/orphan asset bytes from its logical active/partial summary.

SttSettings has HTTP/nativeWhisper kind, model name and explicit endpoint/key. HTTP sends a configured model string; that is server metadata, not an installed local-model selector. NativeWhisperSttProvider always throws unsupportedPlatform/not-installed and does not consume ModelStore or PCM. PCM decode's fake-tested mono16kHz Int16 bytes do not demonstrate whisper inference. Settings still writes legacy BrainSettings fields and first-success checks configuration rather than capability. This plan fixes none of those independent gaps.

## Preserve original198/281 gates

The original full contracts were previously read and retained in merged documentation and source snapshots. Live 198/281 could not be re-read now; no current closed/open/assignee claim is made. Original 281 remains bounded injected storage/tiny synthetic fixtures, excluding production selection/download, native worker, UI/default, memory and hardware qualification. Its acceptance is not reopened by this option research.

Original 198 requires immutable model/backend revisions, format, URL, digest, exact bytes, license/notices and languages; deliberate resumable/progress/free-space/cancel/offline/remove/rollback behavior; separate STT/interface language and RTL choices; downloaded versus loaded state; artifact size separate from measured runtime memory/headroom with Ollama; offline inference; native job lease switch/delete/restart and real hardware evidence. #195 measured default and #197 worker integration remain separate gates. This document does not transfer those owners or relax 351/344/native holds.

## Proposed future metadata and workflow, unselected

1. Review a candidate descriptor containing source repository, immutable artifact commit/path, exact bytes/digest, backend name/version, format, full notices, explicit he/transcribe-only capability and qualification state. Keep it separate from current ModelAsset rather than overloading revision or language labels with untested claims. URL must be immutable and independently read back before any download.
2. Verify final source/redirect/effective destination and disclose one-time model network download, with no microphone/transcript upload. Explicit user action only; never download during voice processing. Check actual disk need and retained leased assets, consent before large download and keep progress/cancel/failed state truthful.
3. Use storage core admission/hash verification and previous selection preservation without promising universal crash rollback. Resume only for same pinned identity and verified offset semantics. A replaced source or mismatch is failure, not a silent different model.
4. Native worker must hold ModelLease for its complete job, own cancel/deadline/crash cleanup and only publish generation-current final text. Stop late-result fencing is not native termination. Unsupported/missing/unqualified model cannot fallback to a cloud endpoint automatically.
5. Present downloaded, verified, loaded, warming, busy, unavailable and removed as separate states once their actual consumer exists. Unsupported language/translation is explicit; profile defaults unchanged. Memory admission requires measured supported devices with Ollama loaded, not file size/free disk or guessed RAM.

## Tiny fake-only next tests

Existing core fixtures already cover mismatch/missing files/restart/leases; do not duplicate them as 'new ivrit inference'. A future adapter slice can use 5-byte fabricated model data and an injected fake worker:

- Pinned descriptor missing bytes/hash/notices/backend rejected before transfer; CT2/GGML identity confusion fails compatibility.
- Mismatch never activates or starts worker; missing/wrong-size selected file yields typed modelUnavailable without network fallback.
- Same-size changed restart bytes exercise the existing documented no-rehash boundary, not an invented repair policy.
- Explicit he/transcribe-only profile validation; auto/translation/mixed profile requests rejected or routed only under a reviewed separate choice, never silently changed.
- Held transfer/cancel/delete/switch plus leased fake job; late result generation fenced, failed shutdown/deletion truthful and cleanup deterministic.
- Offline restart with fabricated installed bytes and zero downloader calls; missing model never auto-downloads. Invalid/timeout/crash worker outcomes do not reach brain/tools.

These tests would prove wiring and failure contracts only. Real Hebrew/code-switching/noise accuracy, CPU/Metal/backend compatibility, latency/RAM/energy, signed offline clean installation and supported phone/Mac permission behavior remain qualification work. No large artifact or private audio in required free CI.

## Fresh validation and sources

**178 unchanged tests passed**, 0 new, across model_store, model_manifest_boundary, model_restart_characterization, model_inventory_characterization, model_registry_composition, stt, stt_deadline, pcm_decode and pcm_decode_boundary. Analysis no issues; format 273 files, 0 changes. No model/network/microphone/native inference/device memory benchmark. Exact-head static/test/linux/security/docs and manager review remain PR gates; Refs-only preparation.

Primary sources fetched 2026-10-11:

- [Hebrew source model card](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo): training/license/task limits.
- [Source card text](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo/blob/main/README.md): card metadata and limitations.
- [GGML card](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml), [file listing](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/tree/main), [file pointer](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/blob/main/ggml-model.bin), [immutable commit](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/commit/2130c78e4a9cb4914cc4df91a1c3031407789705): artifact compatibility claim, revision, exact bytes and SHA256.
- [CT2 card](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ct2), [listing](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ct2/tree/main), [file](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ct2/blob/main/model.bin), [dated card](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ct2/blob/2025.04.03/README.md): separate runtime/artifact route, not native qualification.
- [Ivrit leaderboard](https://ivrit-ai-hebrew-transcription-leaderboard.hf.space/): public corpus descriptions; attribution caveat above, no numerical recommendation.
