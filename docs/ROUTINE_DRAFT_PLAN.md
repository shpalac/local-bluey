# Local-only Routine draft proposal

Audit 2026-10-11, main `fa6548a`. Refs #563. DRAFT/UNADOPTED, sole new doc: source/fabricated-data preparation, not a generator, model deployment, accepted schema/fallback, captured activity, new persistence or runtime consent. #557 is blocked:owner; #561/upstream candidate contracts remain unaccepted. #351/retained-provider/retained-operation decisions stay with the owner. ADR-001/PR651 is a proposal, not permission despite contradictory backlog wording.

## Decision and current evidence

Separate a reviewable draft from a stored/enabled Routine and from tool execution. A local endpoint and a model-shaped JSON response establish neither privacy nor a safe instruction. Reuse existing owners only after a reviewed draft contract exists. No model/version, prompt, temperature, numeric budget, fallback content, policy or new storage is selected here. No model, capture, download, endpoint or provider call was made for this plan.

Read complete [Routine/store/import](../lib/services/routines.dart), [OllamaProvider](../lib/llm/ollama_provider.dart), [provider contract/parser](../lib/llm/llm_provider.dart), [retry](../lib/llm/retry.dart), Brain/BrainHost, request-runner routine and safety/privacy paths, existing store/provider/request fixtures and current registry. [PR654/#561](https://github.com/shpalac/local-bluey/pull/654) is an OPEN unwired candidate proposal, not current-main draft input. The approved scoring plan is independent preparation, not an installed prerequisite. No overlapping Routine generator PR was found in the bounded live inventory.

| Current source | Actual behavior | Missing draft boundary |
| --- | --- | --- |
| Routine | name, lowercase trigger, instructions, enabled; constructor/fromJson can default missing fields | No proposed schema/version/provenance/review/approval lifecycle; legacy parsing is not strict model validation |
| Store/import | Existing routines.json, ordered operations, staged write/rename before memory publication; pack size/count/field limits, whole-pack validation/collision rejection | Not encrypted ActivityStore or new draft store. Import stores data only; add/remove/import/clear are real persistence and must not run during preparation |
| Match/request runner | Enabled nonempty substring trigger matches utterance, expands routine instructions into the request | A generated draft imported with enabled default true could become standing instructions. Draft generation/review is not activation or execution permission |
| OllamaProvider | Configurable baseUrl/model; api/chat text/tools payloads, no format/schema field; tools path can return ToolCall; stream parser handles done/error | Provider name/default localhost does not ensure isolation, local model execution, whole-call deadline or draft-only output |
| Brain/retry | Brain carries conversation/memory/tool context; socket/timeout retries bounded by attempts/backoff, no cancellation/whole-call deadline guarantee | Do not route draft generation through conversation/tool history or use retries as proof of safe completion. Retained-host policy remains separately unresolved |

Routine import accepts a list or version1 wrapper, max256Ki characters/100 routines, fields80/120/4000 code units, rejects duplicate names/types/empty values before write, and enabled omission/null becomes true. Extra properties are not a strict schema rejection. These are existing compatibility facts, not the proposed draft defaults or security guarantees. Store staging cleanup catches deletion failure without an independent erasure receipt; don't infer verified cleanup from an exception.

## Local model and validation are separate gates

Ollama structured outputs accepts format=json or a JSON schema; official examples then independently validate the returned content. Current provider does not request that format. Ollama FAQ/cloud docs describe local-mode controls, including OLLAMA_NO_CLOUD, and cloud models reachable through a localhost API. Thus loopback HTTP alone does not establish off-device isolation. Any future local-only generator must verify both destination and selected local execution mode/version/model, redirects/proxy behavior and process/network boundaries under the existing owner policy; no environment setting was changed here.

Use a dedicated draft-only adapter with no tool definitions, images, conversation memory or raw ActivityStore data, if separately reviewed. Treat input candidates and model output as untrusted data, never instructions for this assistant or an execution host. Unknown local/privacy/readiness status returns prerequisite-unavailable, not remote fallback or permission. Structured format, temperature0 and model availability are not deterministic semantic correctness, confidentiality or execution safety proof.

## Proposed typed contract and staged plan

A future DraftRequest should bind schema/source/candidate revision, reviewed opaque candidate identity, explicit language, authorized sanitized input snapshot, local provider/model identity and cancellation generation. A DraftResult should distinguish proposed, invalid, unavailable/offline, unsupported-format, deadline/cancelled/stale and failed, with safe reason codes and reproducible provenance. It must not be a RoutineStore mutation or ToolCall. A later reviewed adapter to legacy Routine is separate from approval, activation and execution.

Schema review should require explicit version/type/required keys, reject extra privileged/tool/action fields, wrong types/nulls/empty or oversized content and invalid nested shape. Parse exactly one complete JSON value, then validate schema and domain rules; don't extract a convenient JSON-looking line from explanatory prose. Define duplicate-key handling, depth/byte/code-unit limits and Unicode/RTL controls before implementation. Dart jsonDecode/JsonDecoder parses JSON and throws on malformed text, not a Routine domain validator. Required and additionalProperties rules are distinct in JSON Schema.

A deterministic fallback must be separately reviewed, content-free and draft-only, or unavailable with an explicit reason if no safe fallback exists. No fabricated draft text, auto-enable default, cloud fallback or product workflow DSL is selected here. Preserve original invalid/failed result when fallback is proposed; do not turn a malformed response into apparent successful model validation.

| Future stage | Fabricated negative fixtures before implementation |
| --- | --- |
| Snapshot/local gate | Missing upstream/version, stale candidate, privacy read error, remote/LAN/.local URL, local API selecting cloud model, redirect/proxy escape, denied consent; no transport/capture on refused entry |
| Parse/validate | Truncated JSON, prose+JSON, multiple values, duplicate keys, list instead of object, unknown schema, extra tool/permission fields, wrong types/null/empty/oversize/deep input, quoted hostile strings |
| Language/content | Preserve Hebrew without translating evidence, RTL/bidi review, stable opaque identifiers, unsupported language explicit; fabricated text only, no raw screen title/OCR/audio/private corpus |
| Completion | Fake held response, delayed stream terminal, parse failure, cancelled/superseded generation, entered work cleanup, late result cannot publish/persist/execute; deadline observation is not transport termination |
| Review/activation if separately assigned | Draft edits and approvals bind exact version/recipient app/words; failed save leaves prior store, disabled status explicitly selected, duplicate/substring trigger collisions reviewed; never invoke tools during generation |
| Restart/delete if authorized later | Corrupt/incomplete store, failed stage/commit/delete, queued vs entered clear and partial cleanup; registry/retention decisions remain separate, no silently dropped draft/never choice |

## Privacy, failure and rollback

Transport logs/artifacts must use allowlisted safe metadata, never prompts/output/raw user activity, keys, private paths or images. Current provider status errors can include response bodies; a future draft edge needs generic typed failures without adopting a broad error/persistence refactor. No real private log was retrieved. Existing egress metadata is selected-caller, mixed-unit evidence, not packet totals, confidentiality or server-local execution proof.

For a future reviewed implementation, invalidate publication on cancel/revoke/clear, own entered response/parse/cleanup futures and report termination uncertainty honestly. Keep original attempt evidence; do not retry until valid or silently emit a permissive fallback. Requests that could persist or execute require their own owner/user authority and existing SafetyGate, not consent inferred from candidate acceptance.

Rollback future draft wiring without deleting existing routines or changing their matching/import semantics. Preserve schema/provenance/failed-attempt receipts and verify no late save or action can occur. No rollback, store mutation, new fixture, UI/golden, provider configuration, installed model, workflow/schedule/security/threshold or shared-doc change was performed in this PR.

## Validation and primary sources

Fresh unchanged command: `flutter test test/routines_test.dart test/provider_retry_test.dart test/provider_stream_test.dart test/privacy_guard_test.dart test/request_runner_test.dart --reporter expanded`:158 passed,0 new tests. Analyze clean; format273/0 changed, generated SDK paths restored. Existing synthetic/file-temp/mock-client contracts only, not new draft regression coverage or actual isolated model/native acceptance. Exact-head static/test/linux/security/docs and manager APPROVED remain required before auto/squash; this issue stays OPEN/partial preparation.

- [Ollama structured outputs](https://docs.ollama.com/capabilities/structured-outputs): schema format and independent validation; current Cloud structured-output limitation, not a tested installed version.
- [Ollama announcement](https://ollama.com/blog/structured-outputs): dated2024-12-06 historical support, not current deployment proof.
- [Ollama API source](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md): chat/format/stream/done envelope reference; upstream main not a pinned executable contract.
- [Ollama FAQ](https://docs.ollama.com/faq) and [Cloud](https://docs.ollama.com/cloud): local/cloud mode controls and local API cloud-model boundary, no configuration applied.
- [JSON Schema objects](https://json-schema.org/understanding-json-schema/reference/object): properties/required/extra properties/null rules and draft-specific caveats.
- [Dart jsonDecode](https://api.dart.dev/dart-convert/jsonDecode.html) and [JsonDecoder](https://api.dart.dev/dart-convert/JsonDecoder-class.html): parsing one JSON value/FormatException, not domain or permission validation.
