# VAD and speaker verification research

Research: 2026-10-11. Refs #586. Main `3caf8a2`. First-stage research only, not #586 implementation or acceptance. No audio collected, model downloaded, enrollment persisted, authentication enabled or native/provider change. #587 stays blocked; SafetyGate confirmation is not replaced by a voice score.

## Answer

Sherpa-onnx and Silero are not equivalent alternatives for speaker authentication. Silero VAD detects speech activity; sherpa-onnx supplies a wider runtime with VAD and separate speaker-embedding/enrollment/search APIs, and can run Silero ONNX VAD. Speech detection does not establish identity. Embedding similarity does not establish a live human or replay resistance. The issue's 'Replay cannot authenticate' criterion remains unproven and must not become an absolute security claim from either library's demo.

For a future VAD-only slice, compare direct Silero ONNX against sherpa-onnx hosting the same pinned detector before selecting a package. For speaker verification, research a separate licensed embedding model and spoof/liveness boundary; keep action confirmation independent. No library/model/default is selected here.

## Actual Bluey boundary

Complete [STT](../lib/services/stt.dart), [request seam](../lib/services/request_interfaces.dart), [runner](../lib/services/request_runner.dart), [SafetyGate](../lib/services/safety_gate.dart), [tools](../lib/llm/tools.dart) and [PCM contract](../lib/services/pcm_decode.dart) were reviewed with current tests and pubspec. No sherpa/Silero dependency or production VAD/speaker consumer was found in the lib/test/package search.

TranscriberLike returns one final string from a file and SttSettings. It has no streaming chunk/revision, detector state, job cancellation or enrollment interface. NativeWhisperSttProvider always throws unsupportedPlatform/not-installed. Existing PCM decode provides bounded mono16kHz Int16 output; converting/scaling it into a selected detector's float tensor and maintaining recurrent state are new work. Decoder tests do not demonstrate microphone timing, inference quality or streaming.

RequestRunner executes only final transcription and fences late results by generation/deadline. Timeout does not terminate an entered native worker. SafetyGate uses explicit GUI risky-tool confirmation and kill generation; a speaker score cannot toggle or bypass it. Original STT200/VAD/native195/197 work is separate, as recorded in [STT readiness remainder](STT_READINESS_REMAINDER.md); no existing owner or policy gate changes.

## Capability comparison

| Dimension | Silero VAD | Sherpa-onnx |
| --- | --- | --- |
| Role | Speech/non-speech detector, not speaker enrollment/verification. | Runtime/API family including ASR, VAD, speaker embedding, search/verification and diarization. These are distinct functions. |
| License evidence | Repository advertises MIT for Silero VAD. Its README has other ecosystem badges; review the exact pinned artifact/license, not a badge for another package. | Repository Apache-2.0. Individual pretrained model license/provenance must be checked separately. |
| APIs | Official Python/PyTorch and ONNX examples; streaming recurrent state/window handling required. | C/C++ plus Dart and other bindings; speaker extractor and embedding manager APIs, CPU/provider configuration. |
| Audio contract | README supports 8kHz and 16kHz; current wiki examples use 256/512-sample windows respectively, 32ms. | Selected VAD/embedding model controls input contract. Example speaker model is16kHz, not a guarantee every model supports every language/device. |
| Platform claims | ONNX permits deployment through a chosen runtime; Python demo dependencies are not a Flutter native integration. | README lists macOS/Linux/Windows/Android/iOS architectures and Dart support; availability is not Bluey signed-bundle/runtime qualification. |
| Replay defense | None established by VAD evidence. | Speaker similarity demo is not a spoof detector or proven live authentication. |
| Cost/evidence | README claims <1ms for 30+ms chunk on one CPU thread, without a Bluey device/version protocol. | Runtime/model/provider/device determine memory and latency; no Bluey measurements here. |

The [sherpa speaker API](https://k2-fsa.github.io/sherpa/onnx/c-api/html/speaker_embedding.html) shows `SherpaOnnxCreateSpeakerEmbeddingExtractor`, manager enrollment and search with example threshold 0.5. That threshold is illustrative, not a calibrated operating point. The [combined VAD/speaker demo](https://github.com/k2-fsa/sherpa-onnx/blob/14280725/python-api-examples/speaker-identification-with-vad.py) is executable example code, not an anti-replay evaluation. The [Silero issue630](https://github.com/snakers4/silero-vad/issues/630) reports an RKNN conversion limitation involving sample-rate branching; it is a platform-specific community report, not a general failure or current-device certification.

## Replay, consent and error-rate evidence

A recording contains the target speaker's vocal traits and may score as that speaker. VAD merely admits voiced sound. A random spoken challenge can raise the cost of a fixed recording but does not prove resistance to synthesis, voice conversion, relayed live speech or prompt leakage. No assertion that replay can never authenticate follows from this research. A selected anti-spoof model, attack-specific evaluation, hardware capture binding and fail-closed second-factor design need review before #587.

[ASVspoof2019](https://www.asvspoof.org/index2019.html) and its [evaluation plan](https://www.asvspoof.org/asvspoof2019/asvspoof2019_evaluation_plan.pdf) separate physical-access replay from logical-access synthetic/converted speech. The plan uses minimum normalized tandem detection cost as primary metric and equal error rate as secondary; both depend on dataset, scores and assumed costs/priors. Physical-access conditions include simulated room/reverberation/distance/replay quality; the organizer later released 2700 real recorded/replayed files from three labs. That is not Hebrew household/macOS/iOS acceptance evidence.

No comparable published Hebrew/device-specific FAR/FRR/EER or spoof error rate for these two candidate integrations was found in the inspected sources. Do not invent a number or substitute vendor speed/language claims. A future report must identify model hash/version, corpus license and consent, speaker-disjoint development/test sets, replay/synthetic/unknown-speaker attacks, microphone/room/device, threshold selected only on development, FAR/FRR and spoof acceptance at the deployed threshold with trial count/uncertainty. EER is a summary, not the shipped threshold; zero accepted attacks in a finite test is not a universal guarantee. Separate VAD onset misses/false alarms/tail loss from speaker and spoof errors.

Enrollment is sensitive biometric data. A future design needs explicit opt-in, default-off collection, visible recording purpose, minimum retention, encrypted template storage, revoke/delete and failed deletion status. Do not reuse ambient/wake/STT audio for enrollment or upload it by default. No voice-only authorization of purchases, credentials, destructive actions or SafetyGate bypass. Uncertain/noisy/short/no-speech/spoof/unsupported states must deny verification and offer the established human confirmation route, not silent cloud fallback.

## Proposed typed seams and tests, not implementation

- VAD session: pinned detector id/version, sample format/rate, recurrent state owned by job generation, bounded chunk/backpressure, start/end timestamps and final flush. Reset on Stop/restart/model change; no carry of private samples across jobs.
- Speaker assessment: claimed enrollment id plus consent revision, pinned embedding model, minimum eligible speech and detached scores. Result is verified/unverified/insufficient/unsupported/timeout/cancelled, never an action grant.
- Spoof assessment: separate model/attack scope and calibration evidence; unknown or missing evidence cannot be 'live'. Keep all authentication claims disabled until accepted threat model and selected second factor.

Fake-only next tests can cover silence/onset/tail boundaries, sample-rate/channel/odd bytes, bounded chunk queue, reset/cancel/late output, empty/NaN/dimension-invalid embedding, unknown/revoked enrollment, held worker timeout, replay-label denial through the proposed policy and no interim-text tool execution. Fabricated embeddings/labels prove control flow only, not biometric/replay accuracy. Real public licensed corpus, device energy/latency/memory, Hebrew/code-switching/noise, consent UI/delete and attack trials remain separate selected work.

## Validation and open choices

Fresh **164 unchanged tests passed**, 0 new, across stt, stt_deadline, pcm_decode, pcm_decode_boundary, request_runner, safety_gate, safety_gate_lifecycle and privacy_guard. Analysis no issues; format 273 files, 0 changes. Synthetic/fake boundaries only; no native inference, audio collection or anti-spoof benchmark. Exact-head required static/test/linux/security/docs CI and manager review remain PR gates.

Choices still needed: VAD-only scope/runtime, detector/embedding/spoof artifact revisions/licenses, threat/consent/retention policy and calibrated second-factor acceptance protocol. Research does not implement generic issue checkboxes, shared architecture changes or #587. Keep existing native/policy holds.

## Sources

Fetched 2026-10-11. Primary documentation unless marked community; mutable pages need revision pinning before implementation.

- [Sherpa repository](https://github.com/k2-fsa/sherpa-onnx/): runtime capabilities, platforms, languages and Apache-2.0.
- [Sherpa Silero documentation](https://k2-fsa.github.io/sherpa/onnx/vad/silero-vad.html): supported converted VAD artifacts.
- [Speaker API](https://k2-fsa.github.io/sherpa/onnx/c-api/html/speaker_embedding.html) and [identification guide](https://k2-fsa.github.io/sherpa/onnx/speaker-identification/index.html): separate extractor/manager/model roles.
- [VAD/speaker example](https://github.com/k2-fsa/sherpa-onnx/blob/14280725/python-api-examples/speaker-identification-with-vad.py): demonstration, not authentication evidence.
- [Silero repository](https://github.com/snakers4/silero-vad): MIT, rate and vendor speed/training claims.
- [Silero examples](https://github.com/snakers4/silero-vad/wiki/Examples-and-Dependencies): chunk/state/dependency usage.
- [Silero630](https://github.com/snakers4/silero-vad/issues/630): community conversion report, limited generality.
- [ASVspoof2019](https://www.asvspoof.org/index2019.html) and [evaluation plan](https://www.asvspoof.org/asvspoof2019/asvspoof2019_evaluation_plan.pdf): independent attack/metric protocol, not candidate performance certification.
