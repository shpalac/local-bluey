# Egress evidence remainder

Audit: 2026-10-11. Refs #479. Source baseline: main `efd038358cbc5236932363bb3a7a54f3cd279b97`. Source and unchanged synthetic fixtures only, not an allegation of private data leakage or a measured network capture. No real endpoint, private text/audio/image, model, native resource or policy was selected or used.

## Current answer

[EgressMonitor](../lib/services/egress_monitor.dart) provides bounded ordered retained metadata. It is not a central HTTP wrapper, complete transport audit or remote-delivery receipt. Eight explicit production record sites have different timing and units. Concrete brain nonstream calls record after HTTP response, while STT/TTS/model-list checks record before transport. Both brain stream paths and Diagnostics' header probe have no record site. A missing row cannot prove no request, and a present row cannot prove successful delivery or the bytes that crossed a socket.

Original [#58](https://github.com/shpalac/local-bluey/issues/58) is closed by [PR73](https://github.com/shpalac/local-bluey/pull/73), PR head `3f568611188c616bd7b3f968776b69659b717f17`, merge `acec3372e02a8e79bd4ed830aebf0e433bd3b3ee`. The original required a single HTTP wrapper, exact run summary, local-only rejection and matching UI/docs. Its historical "every transmission" prose exceeds current source. No wrapper or enforcement test prohibiting all direct clients was found in the inspected lib/test sources. Do not infer those original acceptance criteria merely from closure.

Delivered [#286](https://github.com/shpalac/local-bluey/issues/286)/[PR291](https://github.com/shpalac/local-bluey/pull/291), head `8f68464c84ee3345e7fa009bf510f693f58c0b41`, merge `f26f3e35a573a960957afc7ea790760fd3feb91f`, repaired restart/history/ordered deletion. Delivered [#297](https://github.com/shpalac/local-bluey/issues/297)/[PR299](https://github.com/shpalac/local-bluey/pull/299), head `b413960b1c4d8343b200fec30839ac2912cc99e9`, merge `4f60692de31691bb39e6c14b0152a7da3834beca`, aligned retained-host classification. Required static/test/linux/security and docs are SUCCESS on both live PR records. Historical extracted-core/classifier checks are not this audit's actual Flutter totals. Do not duplicate these fixes.

Retained endpoint [#459](https://github.com/shpalac/local-bluey/issues/459) remains open; [PR460](https://github.com/shpalac/local-bluey/pull/460), head `91838d1cc25cda445ba3ad59ef6cc2339b847f02`, merge `24c56439c5debf13c5998efccaf1a042da3f860f`, delivered intercepted actual-object request/watch compositions. Its 21 fixtures characterize concrete URLs, not bytes leaving a device. Retained-operation policy and #351 consent/image choices remain unchanged and outside this report.

## Every current record site

| Caller / path | Entry timing and reported amount | What this does not establish |
| --- | --- | --- |
| [OpenAI-compatible](../lib/llm/openai_compatible_provider.dart) chat + chatWithTools (2 sites) | After awaited post returns, before status/JSON validation; brain, JSON String.length. | UTF-16 code units, not UTF-8/wire bytes or content categories. Transport throw before return produces no row; HTTP/parse failure after response can have a row. |
| [Ollama](../lib/llm/ollama_provider.dart) chat + chatWithTools (2 sites) | Same post-response pattern, brain, JSON String.length. | No successful model answer/receipt guarantee. Images are encoded in request payload but not labeled independently in metadata. |
| Both concrete chatStream paths | No EgressMonitor.record invocation, although actual client.send can enter. | Stream requests and partial/failed streams are not covered by these nonstream record sites. |
| [STT](../lib/services/stt.dart) (1 site) | After local-only/file/multipart preparation and active checks, before send; transcription, current audio file length or0. | Not multipart/form/model/headers/response wire size. A recorded attempt can fail or expire; entered transport may continue. No record if refused/missing/empty/preparation-expired before site. |
| [Speech](../lib/services/speech.dart) (1 site) | After privacy refusal, before post; tts, text.length. | Input UTF-16 code units, not JSON/audio/request/response bytes. Failed/timeout/rejected speech can leave metadata. |
| [EndpointAssistant](../lib/services/endpoint_assistant.dart) (1 site) | After URI shape check, before model-list GET; endpoint-check,0. | Not zero network bytes, model/auth readiness or delivery. Direct assistant has no local-only read; caller context matters. |
| [Settings connection test](../lib/ui/settings_screen.dart) (1 site) | Awaited settings-test0 after first verified privacy check; privacy rechecked after recording before provider call. | New privacy intent can prevent transport after this row. Successful nonstream provider may add another brain row, so calls are not unique requests. |
| [Diagnostics](../lib/services/diagnostics.dart) header probe | Actual bounded/privacy-checked GET, no record site. | Successful reachability headers do not mean STT/model/auth readiness or complete egress coverage. |

The eight explicit sites are four brain, one STT, one speech, one endpoint-check and one Settings site. The two stream methods and Diagnostics are separate uninstrumented paths, not additional record sites. No wrapper or new instrumentation is added here.

[Retry](../lib/llm/retry.dart) permits socket/timeout retries. Brain calls that fail before response are unrecorded; a later response records its own invocation, not all prior attempted sends. Stream tool/result routes, current [RequestRunner](../lib/services/request_runner.dart), [Brain](../lib/llm/brain.dart), [WatchVision](../lib/services/watch_vision.dart) and [ScreenWatch](../lib/services/screen_watch.dart) select providers and privacy/session boundaries; they do not wrap the monitor into a universal transport audit. See [retained-host audit](RETAINED_HOST_REMAINDER.md) and [actual composition fixtures](../test/retained_host_composition_test.dart). Stop/generation fences discard stale outputs, not every entered network effect or metadata row.

## Metadata, history and deletion boundaries

| Contract | Delivered behavior | Limit |
| --- | --- | --- |
| Entry fields | Parsed URL host only, caller kind, clamped nonnegative amount, clock time captured at record invocation before queued storage. | Host drops scheme/port/path/query; no destination-IP/DNS/TLS/redirect identity, request ID, status or ack. Time is record-site time, not send/receive completion. Kind is caller string, not fixed validated categories. |
| Secrets / content | Record never falls back to storing a raw malformed URL; tests reject path/query secret retention. No request payload/key stored by current callers. | Host/kind still metadata, not a secrecy classifier. API does not redact arbitrary supplied kind/host strings; no total string/log-byte cap. Report/selftest can echo configured URLs, so not a credential-safe export promise. |
| Recovery | Startup and first record load storage; parse valid rows, flag incomplete lines, retry unreadable loads. Missing file becomes known empty retained history. | historyAvailable means no known recovery/storage error, not full capture coverage. Corrupt rows are skipped, disk preserved while incomplete; no historical no-egress conclusion. |
| Retention / report | Oldest-first sort, age30days/count300 prune; report groups host/kinds/amount/last retained time and warns unavailable/incomplete. | Bounded retained record, not all-time transmission list. Pruning does not itself persist until a write; public mutable entries are not an immutable authenticated ledger. |
| Persistence | Load/record/clear share one ordered queue; records persist only after healthy recovery. Storage write failures set unavailable warning, queue remains usable. | record can complete without disk write after read/corruption/write failure. Most sites unawaited; request completion is not flushed durable metadata. Flush:true file write is not transactional/crash/OS durability proof. |
| Clear | Waits for older operations; delete failure propagates and marks unavailable; success resets history. Fresh post-clear records survive. | In-memory rows clear before disk deletion, and failed deletion can reload retained disk later. Transport that calls record after clear is fresh metadata even if request entered earlier. Not physical erasure, remote deletion or traffic cancellation. |
| Locality | [PrivacyGuard](../lib/services/privacy_guard.dart) uses shared loopback host policy, no DNS; rejects LAN/mDNS/malformed/unknown metadata as confirmed local. | Host classification is not socket-destination measurement or sandboxing. Local endpoint services may themselves send data onward. #351/watch and retained-operation policy are not changed. |
| Offline self-test | Loads history, warns unknown history, checks BrainSettings brain/legacy transcription fallback/TTS and retained host labels. Does not send a canned request or resolve DNS. | Does not use actual SttSettings kind/baseURL; may check stale legacy/default brain value instead of active STT. Empty problems is not a live offline/zero-egress proof. |

## Actual UI and source wording

An all-lib search found report and offlineSelfTest definitions but no production UI callers. [DataRegistry](../lib/services/data_registry.dart) and [DataPrivacySection](../lib/ui/data_privacy_section.dart) show inventory/retention and clear controls, not a dynamic report or self-test button. [README](../README.md) says Settings shows a "verifiable record of what was sent" and "offline self-test"; actual registry calls it "what left the Mac". Monitor comments say "bytes transmitted" and "every configured endpoint must resolve". These are precise wording/consumer gaps, not a reproduced user incident. Existing guide already warns that history is bounded and absence is not no transmission. No README/UI/source comment is altered under this sole-doc task.

Original58's shared-wrapper, exact-byte/data-category, all-HTTP coverage and active self-test/UI acceptance remain unsupported by this inventory. Existing privacy gates and tested STT redirect/deadline protections are separate from metadata. The monitor itself blocks no network request. No no-leakage, physical-erasure or remote-receipt claim is supplied.

## Smallest independent options, all unselected

| Manager option | Bounded independent preparation | Still separate |
| --- | --- | --- |
| Metadata semantics | Specify attempted/response-observed meaning and per-kind units; injected UTF-8/headers/multipart/failed-transport inventory. | No receipt claim or production wrapper selected; bytes policy and coverage need explicit disposition. |
| Coverage fixtures | Actual concrete stream/nonstream/throw/retry/STT/speech/check calls with network-forbidden clients and isolated monitor storage. | Existing459 URL characterization retained; no real endpoint/private payload or changed provider routing. |
| Self-test configuration truth | Specify actual STT-versus-legacy configuration contract and honest unknown/offline labels. | No server/model probe, changing privacy/defaults or activation without separate scope. |
| Current wording / UI contract | Exact source-backed docs/registry/report terminology and optional report/flush presentation specification. | README/UI edits not assigned here; safe export/redaction and interaction behavior need separate selected work. |
| Ordered evidence lifecycle | Define when request IDs/stages/durability/clear should settle in deterministic fixtures. | No duplicate291history fix, traffic cancellation, immutable audit, physical erase or server ack invented. |

No option is selected. Shared owners, #351/#344/native/provider/retained-operation holds and defaults remain unchanged. This document closes no issue and transfers no ownership.

## Fresh validation

Pinned Flutter3.47.6/Dart3.13.5, locked dependencies; analysis no issues. **213 unchanged tests passed** across egress_monitor/privacy_guard/provider_retry/provider_stream/STT/deadline/speech/speech_failure/settings_deletion/privacy_docs_contract/endpoint_assistant. **64 additional unchanged tests passed** across privacy_clear_widget/retained_host_composition/data_registry/diagnostics_provider. Total277, two explicitly separate completed runs. Earlier progress post incorrectly said74 for the second run; the observed log is64. No new fixtures or source changes.

These use synthetic injected storage/clock/preferences, MockClient/network-forbidden clients, generated file bytes and isolated temporary telemetry. No real network/private audio/model/device/energy proof. Complete rendered note/tables and local links are inspected before publication; required/docs CI and exact-head approval remain separate PR evidence.
