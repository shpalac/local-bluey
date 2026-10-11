# STT readiness remainder

Audit: 2026-10-11. Refs #467. Source baseline: main `9bb59d99d53282af6bbe46a047bed0078732a97e`. This is a source and unchanged-fixture audit, not a native inference, audio-quality or hardware qualification result.

## Current answer

The final-file HTTP provider and RequestRunner already have deterministic deadline, generation, redirect and queue protections. Do not assign those repaired slices again. Native whisper remains an explicit not-installed provider. The decoder is delivered prework, not a worker. Saved configuration is not capability readiness, and the advertised typed-input alternative is not wired to production request dispatch at this baseline. No provider, policy, model or follow-up is selected here.

Original [#196](https://github.com/shpalac/local-bluey/issues/196) is closed. [#197](https://github.com/shpalac/local-bluey/issues/197) remains open and assigned to shpalac; its Oct 8 comment retains the claim and holds the gated remainder. [#199](https://github.com/shpalac/local-bluey/issues/199), [#200](https://github.com/shpalac/local-bluey/issues/200), [#201](https://github.com/shpalac/local-bluey/issues/201) and benchmark decision [#195](https://github.com/shpalac/local-bluey/issues/195) remain open. This document changes none of their disposition or ownership. Full bodies and comments were read, including the filing-time assertions superseded by later delivery.

## Delivery provenance, not fresh test totals

| Delivery | Verified merged commit | Scope and limits |
| --- | --- | --- |
| [PR207](https://github.com/shpalac/local-bluey/pull/207), closes196 | `c33de337604a666d936048a5bc56a282e83e58f9` | Independent settings, provider seam, structured errors; not installed native inference. |
| [PR211](https://github.com/shpalac/local-bluey/pull/211) | `56fb3474c84fff4bc2983ae2d22a1a2291275fbb` | Runner resolves saved kind per request; main no longer pins HTTP. Injected transcriber still wins. |
| [PR209](https://github.com/shpalac/local-bluey/pull/209), refs199 | `e86bac9ed08b545b1d99971bc5697bd2aab2f922` | Earlier generation/deadline/redirect slice, not full199 closure. |
| [PR253](https://github.com/shpalac/local-bluey/pull/253), refs249 | `b3f07abf5fccbb3aba5e0bdd334e73b0f84ef33f` | Clear tombstone prevents legacy STT revival; secure deletion failure is reported. |
| [PR306](https://github.com/shpalac/local-bluey/pull/306), closes305, refs199 | `71d04180b3ffdfcda59e0f8b178575ca7d7ec17c` | Generation and whole-job budget around each awaited runner stage; late result discard, not transport/native abort. |
| [PR314](https://github.com/shpalac/local-bluey/pull/314), closes313, refs199 | `ae1c6abebb7b5846b508dd08726ff694bb42ebbc` | One elapsed HTTP invocation budget and owned body-listener cancellation, not shared-client closure or upload abort. |
| [PR370](https://github.com/shpalac/local-bluey/pull/370), refs366 | `d1e1020ad5605477195d9dca795e82e62fa264c6` | Serialized request intake, two waiting utterances by default, admission generation and cleanup. Phone fixtures are synthetic. |
| [PR231](https://github.com/shpalac/local-bluey/pull/231), refs197 | `075b33cd6c639ac502d0dfeab1a2c679cf8e09a3` | AVFoundation decoder/channel prework, not whisper integration. |
| [PR343](https://github.com/shpalac/local-bluey/pull/343), closes342, refs197 | `acf6cb8332e03aaedc24f9b46e74db19534947b6` | Dart PCM output validation and generic failure boundary; fake channel/file/bytes evidence. |
| [PR235](https://github.com/shpalac/local-bluey/pull/235), refs226 | `7cacd250ed6f4a3aab828e93f7b3cee232fc0147` | First-success plan and configuration-only STT check. PR explicitly records configured dead/native providers can count ready. |

These live PR records establish merged provenance. Their historical worker totals are not this audit's totals and do not prove native runtime. Required CI for this document's future head is separate.

## Actual settings and dispatch

[stt.dart](../lib/services/stt.dart) owns HTTP/nativeWhisper kind, optional endpoint, model and a separate secure STT key. Defaults are HTTP, no endpoint and whisper-1. Load migrates saved `brain.transcriptionBaseUrl` and model once, plus a legacy brain credential into the STT slot when absent. It does not copy the general brain URL as a missing STT endpoint. An unknown kind recovers to HTTP, not a cloud destination. Secure-read failure becomes no key; secure migration failure is skipped while the migration marker is still written.

Save writes the STT key through secure storage and then preference fields. Secure-write failures throw; preference booleans are not checked, and this is not a transactional settings owner. Clear marks the migration tombstone before secure deletion, reports secure deletion failure and then removes STT preference fields. Delete-all also clears legacy brain values before the tombstone is removed. This prevents the tested legacy resurrection, not an OS keychain durability guarantee.

[Strings](../lib/services/strings.dart) keeps interface language and speech language separate. HTTP uses current speech language at request construction: omit language for auto, otherwise send it (including he). Language is not a captured field in SttSettings, and capabilities are not a measured provider matrix.

Actual [SettingsScreen](../lib/ui/settings_screen.dart) loads/saves BrainSettings and still exposes the legacy transcription URL/model form with a brain-fallback hint. It has no SttSettings import/save or STT kind picker. After one-time migration, those legacy form edits are not a production STT configuration writer. Older issue addenda and PR prose describing a picker are not proof of present UI wiring. No Settings change is made by this audit, and #464's replay caller remains independent.

[RequestRunner](../lib/services/request_runner.dart) loads STT settings for each admitted voice job and uses SttProviders unless a transcriber is explicitly injected. [main.dart](../lib/main.dart) passes the actual safety/tools/speech/hooks, not a pinned transcriber. Its request route is `_processUtterance(File)` to `process(File)`; there is no typed-text runner entry point. Settings and watch text fields are configuration, not typed ask.

[Degraded](../lib/services/degraded.dart) returns the text "type your request instead" and the token `typedInput`. An all-lib reference search found no production consumer of those values and no typed request form submitting to the runner. [DeepLinks](../lib/services/deep_links.dart) parsing is also not ask dispatch. Therefore "typed input is always available" in199 and unsupported-platform alternatives in196 remain unverified/unshipped at the actual submission boundary. This is source evidence, not a reproduced device failure.

## Boundary matrix

| Actual boundary | Delivered and tested | What it does not establish |
| --- | --- | --- |
| TranscriberLike | Future of one final string from a file and STT settings; provider injection. | No partial/chunk/revision stream, job cancel method, disposal or model-switch contract. |
| HTTP preparation | Missing configuration is typed; snapshot local-only once; reject remote before file access; missing/empty capture is typed; recheck active after awaited preparation. | No general URL/DNS/effective socket-destination verification. The current loopback classifier includes localhost and 0.0.0.0; this is not a secure bind/exposure policy. |
| HTTP deadline | Default120s from invocation, includes privacy/file/multipart/header/body awaits. Expiry is synchronous; cancels owned body listener; late headers release their stream; shared client stays open. | No preemption of synchronous CPU work, guaranteed upload/header I/O abort, bounded response-byte cap or provider lifecycle cancellation. Cancellation may settle late or fail. |
| HTTP redirect/result | Redirect following disabled; 3xx with Location rejected; status/JSON/text checked; trimmed final text. STT's own credential/model only. | No real endpoint compatibility or model availability proof. Raw HTTP error body is still part of SttException text, not a reviewed all-errors sanitization contract. |
| Runner admission | One active job; default two waiting; excess rejected and recording deleted. Admission generation survives waiting/turn grant. Stop drops old queued work on handoff. | No immediate cancellation of an entered Future or immediate queue draining while the active stage remains held. |
| Runner stages | Default3min whole job/60s step, smaller remaining budget; generation/deadline checks before/after settings, STT, brain, authorization, tools/results and synthesis. Late tokens and outputs fenced. | Already-published actions/text are not undone; entered native/network work may continue. The runner has no dispose/worker-termination contract. |
| Voice cleanup | Runner finally awaits deleteRecording; default AudioCapture.deleteQuietly; rejected queue recordings cleaned. | Best-effort deletion is not physical erasure, crash/restart sweep or cleanup of a future worker's files. |
| Readiness | FirstSuccessPlan combines permissions, brain endpoint check and STT configuration. Diagnostics explicitly reports brain HTTP reachability, not model/auth readiness. | `checkServices` marks any nonempty HTTP URL or native kind ready without STT capability probe. No download/loading/warming/busy/cancelled model states. |
| PCM decode | Dart input cap8MiB, output<=40MiB, mono16kHz Int16 even nonempty bytes, source duration>0 and<=600s, detached readonly result. Native channel registered; Swift decodes off main into memory. | Fake channel/driver tests are not AVFoundation sample quality or native cancellation/crash evidence. Decoder is not consumed by the native placeholder. |
| Development shim | Launcher pins literal loopback route/configuration, disables redirect/proxy upload, Python/ffmpeg adapter translates final file to inference. | Not bundled signed managed worker, authentication of another local process, pinned production model catalogue or shipping native readiness. |

Source paths: [request seam](../lib/services/request_interfaces.dart), [privacy classifier](../lib/services/privacy_guard.dart), [PCM](../lib/services/pcm_decode.dart), [Swift decoder](../macos/Runner/AudioDecoder.swift), [registration](../macos/Runner/MainFlutterWindow.swift), [capture](../lib/services/audio_capture.dart), [readiness](../lib/services/first_success.dart), [diagnostics](../lib/services/diagnostics.dart), [registry](../lib/services/data_registry.dart), [shim](../tool/stt_shim.py), [launcher](../tool/local_stt.sh). Historical [LOCAL_STT](LOCAL_STT.md), [README](../README.md) and [user guide](USER_GUIDE.md) are preserved, not silently rewritten to erase their older routing wording.

## Original acceptance still remaining

- **196:** service abstraction/migration/provider resolution are delivered. Actual user-facing provider configuration, installed-capability choices and typed alternative need their own selected work; structured error enum values alone do not implement native lifecycle.
- **197:** pin a qualified backend/model, managed off-UI worker/bridge with job identity, bounded concurrency, actual cancel/deadline/crash recovery and warm memory policy. Integrate and validate existing decoder. Metal/CPU selection, optional Core ML variant, resources/licenses, signed clean offline macOS14+ installation remain. A development HTTP server must meet its separate local-client/auth/route contract, not borrow the shim's health check as authentication.
- **199:** actual job termination/disposal/model-switch contract, truthful capability/readiness, deliberate installed-local/off-device choices under local-only rules, and typed dispatch remain. Preserve delivered Stop/late-result/whole-body protection. Native diagnostics must not invent HTTP upload events. Worker/crash intermediate cleanup and actual effective-destination evidence are not supplied by these fixtures.
- **200:** phase2 VAD and optional partial display remain unimplemented. Need explicit PCM/chunk/revision/backpressure/finalization/no-speech semantics, detector license, silence/Hebrew onset-tail/noise fixtures, final-only execution proof and measured memory/energy/release latency. Final-file HTTP JSON is not live streaming. No wake-word scope or streaming default is activated here.
- **201:** deterministic existing tests are present, but no selected licensed native public fixture/model, opt-in pinned native inference lane or signed clean-install smoke evidence is supplied. Named Mac/phone Hebrew/code-switching/Stop/sleep-wake/Ollama-pressure results remain. Current macOS/iOS compile and emulator mocked boundaries are not Metal inference. Native lane in [ci.yml](../.github/workflows/ci.yml) is opt-in and does not itself establish a worker exists. Download/offline/profile/removal/size-versus-RAM user and developer docs await selected production contracts.

## Smallest independent options, all unselected

| Option for manager disposition | CI-verifiable injected boundary | Still outside that option |
| --- | --- | --- |
| Truthful STT configuration/readiness | Existing settings loader/provider seam; native placeholder cannot be reported capability-ready. Assert missing/dead/native states without private audio or download. | Real server/model qualification and hardware readiness; Settings/onboarding source coordination required. |
| Actual typed submission | Define one text-to-existing runner/safety/queue boundary with Stop/lifetime tests and real caller wiring, rather than only a fallback token. | Native inference, OS shortcut dispatch and changing action policy. |
| Native job contract prework | Provider plus fake managed-worker job IDs/cancel/crash/late-result/lease contract, reuse validated PCM. Preserve unsupported production default. | Selecting197 ownership, implementing/qualifying a backend, downloads/signing/Mac resources. |
| Phase2 specification/fixture slice | Explicit chunks/revisions/no-speech and execution spy proving interim text cannot reach tools. | VAD asset/license selection, activation and real capture/accuracy/energy evidence. |
| Native validation preparation | Licensed public fixture contract, pinned-input/operator checklist and mock/compile/native labels. | Registering/paying for a runner, secrets, protected release approval or declaring native lane complete. |

These are proposals, not assignments. No ownership transfer, policy/provider/default selection or fourth worktree follows from this audit. Keep197 and existing351/344/native holds unchanged.

## Fresh validation and evidence limits

Pinned Flutter3.47.6/Dart3.13.5 with enforced lockfile. Analysis: no issues. Unchanged run: **135 passed** across stt, stt_deadline, request_runner, privacy_guard, egress_monitor, endpoint_assistant, first_success, pcm_decode, local_stt_tools and degraded tests. These include fake-clock held deadline/listener fixtures, settings reset/migration, Stop+resume/queue and cleanup, mocked PCM and metadata-only fallback assertions.

The local tools test invokes offline loopback Python routing/phone-harness/benchmark-accounting fixtures, including generated audio where tools are present. No production server, model download, private recording, microphone, inference or hardware benchmark was run. First-success tests exercise the pure plan, not a native capability probe. Required/docs CI and exact-head review for this doc are recorded in its PR, not assumed from this local run.
