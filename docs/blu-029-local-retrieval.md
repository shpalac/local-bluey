# BLU-029 local retrieval

This opt-in module depends on BLU-028 `FileIndex`; without a previously consented folder and ready index, all retrieval is disabled. `LocalSemanticRetriever.retrieve` constructs deterministic hashed-token vectors in memory and ranks path-backed excerpts by cosine similarity. It does not call an external embedding provider or access files separately, persist vectors, send telemetry, or execute actions. Empty/invalid requests fail closed; zero matching vectors yield an empty result, never a fabricated citation. Revocation, refresh and restart invalidate results.

This is a lightweight on-device lexical embedding baseline, **not** a learned multilingual embedding model. Synonyms without overlapping tokens are not matched. The module is not yet integrated into the assistant answer pipeline or UI; citations must be rendered as file paths tied to returned excerpts. No automatic permission grant or provider fallback is allowed.

Safety/privacy: source bytes and paths are taken only from BLU-028's memory snapshot and disappear on revocation/restart. Large files are already bounded by the index. Search has a limit and timeout; cancelled requests do not return partial results. Integration with SafetyGate, ActionLog and data registry is deliberately not asserted: retrieval is read-only and has no tool execution. Manual macOS TCC, accessibility, RTL and offline verification remain pending.

Rollback: stop constructing `LocalSemanticRetriever` and invoke `FileIndex.revoke()`; no schema, migration or cleanup process is required.
