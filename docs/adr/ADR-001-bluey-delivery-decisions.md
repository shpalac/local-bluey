# ADR-001: Local Bluey delivery decisions and blocker resolution

Status: **Accepted for implementation planning**, 2026-10-11. Scope: BLU-001–BLU-080. This is a conservative implementation contract, not a claim that code already meets it.

## Ground truth
Existing layers: Flutter UI, Brain, ToolExecutor, SafetyGate, HostControl, PrivacyGuard, EgressMonitor, ActionLog; `.github/workflows/ci.yml` already has Ubuntu static/docs and scheduled security checks. `docs/SUPPORT.md` treats macOS as supported host, iOS/Android as clients, Linux experimental/unsupported by role, Windows unsupported. Preserve existing policies; never weaken them to ship features.

## Decisions (default choices to remove design ambiguity)

1. **Observation consent / BLU-001, 007, 012, 064**: passive watching and Teach Mode are disabled by default, scoped to explicit user-initiated sessions, with a visible indicator and immediate stop. Restart, app lock, permission loss or ambiguous session state stop capture. No background persistence or auto-resume. An opt-in capture session is not consent to execute an automation.
2. **Sensitive frames / BLU-001, 003, 056**: fail closed *before* model inference or persistence when a window/app is denied, classification uncertain, or sensitive content is suspected. OCR/regex are not sufficient proof that a screenshot is safe. Do not transmit/store raw frames as the default. `PrivacyGuard.hasSensitive` is a supplemental heuristic, never the sole guard. Do not claim perfect PII detection.
3. **Storage / BLU-002, 004, 005, 055, 069**: use a typed, versioned activity schema; minimize metadata; no raw keystrokes, screenshots, or full text by default. A proposed 14-day TTL applies only to explicitly opted-in *redacted* activity metadata; approved workflow definitions remain until deletion. Encryption at rest is a release gate for persisted activity: choose a verified implementation after spike, not an unverified SQLite-encryption claim. Until then use in-memory-only capture. Handle SQLite WAL, backups and crash recovery in deletion tests; document limits of secure erasure.
4. **Approval and execution / BLU-014–020, 031, 033**: a learned workflow is a disabled draft until explicit approval. Reuse the existing SafetyGate for each risky action; no voice identity, pattern confidence, MCP server description, or blanket approval bypasses it. Execution is stepwise with preconditions, explicit postconditions, bounded timeouts and cancellation. A successful API call is not proof of real-world outcome.
5. **Retries / BLU-018, 019, 054, 058, 059**: default to **no automatic retry** for non-idempotent external actions (send, purchase, delete, lock/unlock, publish). Retry only when an operation is provably idempotent or has a verified idempotency key; otherwise stop for review. After a crash, unknown outcome remains unknown: never blindly replay.
6. **Model use / BLU-010, 013, 073**: deterministic rules and typed tool APIs first; LLM only for proposals or bounded fallback. Validate model outputs against strict schemas. In local-only mode, no cloud fallback when Ollama or STT fails; show an explicit degraded state.
7. **MCP / BLU-025–027, 033–034, 057**: start with explicitly installed and allowlisted local stdio servers. Server names, tool descriptions and returned content are untrusted input. Tool calls flow through SafetyGate. Never promise process sandboxing or network containment unless measured on each OS; document subprocess egress limitations. No remote MCP by default.
8. **Platforms / BLU-036–042, 048, 070**: macOS host and iOS/Android clients only for first release. Do not claim Linux or Windows host parity. Use standard GitHub-hosted Ubuntu for deterministic Dart tests, standard macOS for native compilation and mocks, Android emulator and iOS simulator only where stable. Real TCC Accessibility/Screen Recording and physical-device acceptance are separate manual gates.
9. **CI / BLU-036–051**: extend existing workflows instead of creating duplicate CI. PR: format/analyze, unit/fake integration, security/privacy tests, relevant builds; scheduled: stress, fuzz, soak, migration and model benchmarks. Required checks fail on test failure; no silent skip, paid runners, cloud secrets, or heavyweight model downloads. Pin third-party actions by commit SHA, least-privilege token, sanitized artifacts.
10. **Workflow format / BLU-014, 015, 052, 074**: versioned JSON DSL with strict validation and no auto-enable on import. Preserve legacy Routine behavior and import/export until explicit migration tests pass. Reject unknown actions/permissions by default; prefer forward-only schema migrations with explicit downgrade error.
11. **Quality / BLU-008, 009, 021, 022, 060–062, 067**: start with transparent rule-based detection and user-adjustable suppression; no autonomous action based on pattern confidence. Benchmark false positives, CPU, memory and p95 latency on synthetic traces, then run opt-in real-Mac pilot. Do not invent pass thresholds before measuring baseline; record baseline first, set thresholds in follow-up PR.
12. **Scope sequencing**: P0 privacy + schema + CI audit; P1 capture/Teach Mode + workflow DSL/executor/verifier; P2 passive learning, MCP and STT benchmarks; P3 Rive, Home Assistant, browser and advanced retrieval. Parallel work may start on independent contracts/tests but must not bypass P0 gates.

## Unblock protocol for all BLU issues
- Treat these choices as approved **defaults for engineering planning**; no need for new product-choice approval to start code or tests.
- Each PR must identify existing exact files and interfaces, test negative cases, document migration/rollback and update acceptance evidence.
- If implementation reveals an incompatibility or a demonstrable safety issue, propose a narrow ADR amendment in the PR; **do not silently override a decision**.
- Runtime permissions, access to user data, and irreversible external actions still require the app's normal explicit user consent.
- Historical issue references in docs/ACCEPTANCE_MAP.md are evidence snapshots, not proof of real-device readiness.

## Suggested parallel start
A. BLU-001/003 privacy gates + fixture corpus.
B. BLU-002/014 typed activity and workflow schemas with pure Dart tests.
C. BLU-036/037/043 CI audit and hardening, preserving current workflows.

## Follow-up verification
The decisions above are architectural. Before declaring any task completed, verify source behavior, tests, exact CI heads and actual hardware gates as required.