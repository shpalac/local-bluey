# Model manager remainder

Audit: 2026-10-11. Refs #468. Source baseline: main `9bb59d99d53282af6bbe46a047bed0078732a97e`. Source and tiny synthetic fixture evidence only. No production asset, download, inference, license qualification or memory benchmark was selected or run.

## Current answer

The verified storage core is delivered. It does not constitute an installed native model manager. [ModelStore](../lib/services/model_store.dart) accepts caller metadata, an injected transfer stream and free-space probe. Actual production references are the [DataRegistry](../lib/services/data_registry.dart) inventory description and clear callback. An all-lib reference search found no production install/acquire caller in STT, RequestRunner or Settings, no catalogue/default/download UI and no concrete network downloader. Native STT still throws not-installed.

Original [#198](https://github.com/shpalac/local-bluey/issues/198) remains open. Its independent fixture-only child [#281](https://github.com/shpalac/local-bluey/issues/281) is closed by [PR292](https://github.com/shpalac/local-bluey/pull/292), merged `937b42aaca5604fb813cd0b4d943142ec89ec558`, PR head recorded by GitHub `4a6a8e64c52f8bfb7b7b592c7269e1ed36b284e7`. Full original bodies/comments and merged PR were inspected. PR292's historical20 fixture tests/full450 total are not this audit's fresh totals. Its later commits include serialized mutation/leases, content-unique paths, epoch parts/coalescing and safe retirement. Do not assign a duplicate implementation of those delivered guarantees. No issue disposition or ownership changes here.

## Manifest and verification are specific contracts

Manifest version1 parses caller-supplied assets. Required typed fields: id, revision, int bytes, SHA-256 string, format and backend. licenseNotice defaults empty if not a string; languages keeps string list elements and otherwise defaults empty. Unknown version is rejected. Parsing is not full semantic install validation: the fixture accepts a placeholder digest at parse time. Install rejects empty notice, nonpositive bytes, non-lowercase64hex digest, and format/backend absent from the store's accepted sets. Empty accepted sets accept none.

The manifest does not contain URL metadata, separate backend revision, model-card identity, signature, translation/auto-language capabilities, RAM estimate or a pinned production catalogue. A nonempty licenseNotice is a metadata requirement, not legal/source/license verification. Language labels are not enforced by a native decoder/inference consumer. The caller supplies those facts; this audit invents none.

Keys base64url-encode id/revision to avoid slash/underscore collisions and directory traversal in generated names. Content filenames append the first32 digest characters, so tested differing content under the same id/revision does not overwrite leased bytes. This is the implemented naming policy, not a full-digest collision proof or arbitrary external-path bug claim. Live folder identity uses `root.absolute.path`, within the actual app support folder contract; it is not an interprocess lock or a filesystem-alias normalization promise.

## Actual lifecycle matrix

| Boundary | Actual behavior and fixture evidence | Important limit |
| --- | --- | --- |
| Explicit install | Only install initiates injected downloader; same filename/delete epoch shares an in-flight transfer. No network connection in the core. | No concrete HTTP adapter, URL allowlist, redirect/range response validation or automatic production asset selection. |
| Disk admission | Creates asset/partial folders, resumes retained byte count, checks freeSpace against remaining declared bytes before transfer. Overlarge retained partial is discarded. | Disk bytes are not RAM/headroom. Probe supplied by caller; no live Ollama memory decision or progress callback. |
| Transfer/cancel | Offset passed to downloader; stream chunks append to epoch-owned partial. Short/interrupted transfer retained for resume; overlong discarded; cooperative token/stale checks prevent half activation. | Token is checked as the stream yields/finishes, not a guaranteed immediate abort of a stalled downloader. No native cancellation or timeout state machine. |
| Integrity/activation | Exact byte count then SHA-256 of partial; hash mismatch discarded. Serialized commit rechecks generation, renames asset, flushes temp selection and renames selection, then prunes inactive files. Tested failed update retains previous selection. | Filesystem transaction/rollback across every possible rename/write/prune failure is not proven; atomic selection publication is not universal crash durability. |
| Restart/read | Reads selection JSON; malformed/type-invalid, missing or wrong-size file returns null. Previously installed synthetic selection survives owner retirement/reopen. | activeAsset does not rehash, revalidate license/backend sets or probe inference on restart. Same-size out-of-band corruption is not ruled out by restart test. |
| Acquire/switch | Serialized lookup+lease registration; old leased content stays while new verified selection activates. Removal cannot race lookup to invalidate a registered lease. | No real worker owns a lease yet. This does not prove safe switch during native inference. |
| Remove active | Bumps generation before queued mutation; removes selection immediately when mutation runs. Active file deleted now or queued for final lease release; entered staged update becomes stale. | Logical availability removal is distinct from physical file removal and no promise of secure erasure. |
| Delete all | Bumps generation/delete epoch, removes selection/temp selection/partials, deletes unleased asset files, defers leased files. Old transfer's epoch cleanup cannot revive selection. | Completion may leave leased bytes until release; filesystem errors are not silently treated as successful erasure. Underlying transfer can still finish late. |
| Release | Per-file count, idempotent lease release; final release deletes pending file through same serialized owner. | This is in-process owned lifetime, not crash/restart lease recovery or guaranteed disk wiping. |
| Retirement | One live owner per absolute folder key. Dispose refused for leases, in-flight transfer or queued mutations; later reads/mutations reject retired owner. | Cross-process ownership, aliases and process crash are not covered by static live map. |
| Registry clear | Resolve app support/models; live owner gets deleteAll and honors leases. With no live owner, temporary no-download owner deletes stored files then retires. MissingPlugin is no-op. | Registry targets this folder only; arbitrary external stores are not this app's inventory contract. No OS plugin/folder evidence from no-plugin test. |
| Inventory | active id/revision/declared bytes plus partial bytes. Registry privacy screen has fixed description and retention text. | Not total disk usage of inactive leased/pending-delete/orphan files, not model-loaded state or resident memory. No production call to dynamic inventory found. |

Full core and [model_store_test](../test/model_store_test.dart) were read, including entered freeSpace/transfer deletion, simultaneous transfer coalescing, same-id/revision changed bytes, acquired/queued lease versus retirement and clear through live/no-live ownership. Generic delete-after-start fixture explicitly does not claim hashing was entered. No stronger race coverage is inferred from a test name.

## Real consumer map

- **Registry:** model_store entry describes app support/models and "nothing is downloaded unasked"; clear is ModelStore.clearOnDisk. [DataPrivacySection](../lib/ui/data_privacy_section.dart) exposes registry clear/delete controls. Existing successful/error deletion handling is not new model-install UI.
- **Settings:** [SettingsScreen](../lib/ui/settings_screen.dart) has brain-era transcription URL/model fields, not ModelStore creation, installed model/profile selector, loaded/backend/RAM state or install/remove workflow.
- **Voice:** [stt.dart](../lib/services/stt.dart) has explicit HTTP plus nativeWhisper placeholder; [RequestRunner](../lib/services/request_runner.dart) resolves saved provider, accepts final file, but does not acquire model leases or invoke install. [PCM decoder](../lib/services/pcm_decode.dart) is delivered standalone prework, not model load/inference.
- **Tests:** actual core is driven with temp directories, generated300byte assets, fake format/backend, injected offset streams and free-space values. Registry tests describe/clear the same core. [dartdoc contract](../test/dartdoc_contracts_test.dart) references the file; that is API documentation validation, not production activation.
- **Development tools:** [local_stt.sh](../tool/local_stt.sh) has its own manual setup/server/model path, separate from ModelStore. It is not the production download adapter or evidence of catalogue pinning/managed native installation. No setup/download was executed here.

Historical README/user guide/issue descriptions remain unchanged. Their model/provider intentions do not supply missing concrete consumers.

## Remaining198 criteria, without duplicate backlog

| Original198 criterion | Delivered slice | Remainder |
| --- | --- | --- |
| Pin revision/format/URL/hash/bytes/license/languages; atomic/resumable install with progress/cancel/offline/remove/rollback | Caller revision/format/backend/size/digest/notice/languages, offset resume, size/hash before activation, injected space, lease-aware remove. | Reviewed production URL/model/backend revisions, source/license qualification, concrete adapter/offline/progress state, network response semantics and full operational rollback evidence. No unpinned executable asset choice. |
| Hebrew profile versus multilingual and explicit he, no unsupported auto/translation | Language labels only; UI/speech language already separate in Strings. | Verify exact candidate cards/revisions/license and permitted modes before selection. Original ivrit-ai/turbo candidates are proposals, not measured defaults. #195 benchmark decides profile/default; this audit does not endorse model/license facts. |
| Profile/model UI, RTL names/URLs, downloaded/loaded/backend state | Registry description and core inventory. | Actual model manager UI and capability validation, installed versus loaded distinction and safe switch/remove caller integration. No permission to alter Settings464. |
| Download size versus measured RAM, Ollama-loaded headroom, deliberate large download, idle unload | Exact download bytes and injected disk-space admission. | Runtime memory/headroom/idle policy and measured quantized variants with actual hardware. Never kill user's Ollama process. |
| Deliberate network download separate from offline inference; registry/delete-all safe during turn | Explicit injected install and lease-aware clear; no voice-side download call. | Concrete deliberate download disclosure, actual worker acquire/release and offline inference/restart evidence. Logical selection deletion is not immediate physical erasure of leased bytes. |
| Interrupted/corrupt/hash/space/model-switch/deletion/restart tests | Tiny synthetic core fixtures for those storage contracts. | Insufficient RAM, real model/backend compatibility/quality, native in-turn switching/removal and offline clean-install durability. |

[#197](https://github.com/shpalac/local-bluey/issues/197) owns native worker integration; [#195](https://github.com/shpalac/local-bluey/issues/195) owns measured decision. Neither is assigned or released by this doc. #281 deliberately removed that dependency only for core fixture work. No production URL/hash/license investigation is necessary here because no production asset is selected.

## Smallest independent options, all unselected

| Manager option | Injected CI boundary | External/selection gate |
| --- | --- | --- |
| Catalogue schema/adapter contract | Define separate URL/backend revision/capability metadata and offset/status/redirect/offline/progress semantics with tiny fixture streams. Keep install explicit. | Reviewed exact asset metadata/licenses/destinations and deliberate product download choice. |
| Restart integrity contract | Select whether to reverify, quarantine or report stale metadata, then deterministic same-size corruption and invalid selection fixtures. | Performance/cost policy and real filesystem durability evidence; existing restart-size check is not automatically a defect to patch. |
| Disk inventory truth | Define total retained/leased/partial/orphan accounting separately from logical selection and estimated RAM; injected filesystem fixtures. | UI wording and deletion expectations; no promise of physical erasure. |
| Worker lease handoff | Fake job acquires/releases actual store lease through switch/cancel/clear/crash contract; no inference backend required to specify it. | Coordinate197 ownership/bridge; actual backend termination and device evidence later. |
| Model-manager presentation specification | Installed/downloaded/loaded/backend/language and deliberate action states with size-versus-RAM labels. | Profile/default/license/RAM decisions and shared Settings source selection before implementation. |

No option is selected. Preserve198/197,351/344/native holds and current defaults; no owner transfer or code/test/asset change follows from this report.

## Fresh validation

Pinned Flutter3.47.6/Dart3.13.5; enforced lockfile; analysis no issues. **75 unchanged tests passed** across model_store, data_registry, settings_deletion, privacy_clear_widget and privacy_docs_contract. Test bytes, streams, platform channels and files are synthetic. No microphone, production network downloader, model fetch, real keychain, native worker, memory measurement or hardware benchmark ran. Required/docs CI and exact-head review for the document are separate PR evidence, not implied by this local run.
