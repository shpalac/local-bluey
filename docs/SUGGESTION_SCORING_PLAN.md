# Suggestion scoring and suppression proposal

Audit 2026-10-11, main `fa6548a`. Refs #562. DRAFT/UNADOPTED, sole new doc: fabricated-data/source-only preparation, not implemented scoring, new persistence, UI, capture or accepted product thresholds. BLU-008/#561 and storage/#557 remain unresolved dependencies; #351/retained-provider/retained-operation choices are owner gates. Issue text claiming ADR-001/PR651 resolves these is not permission. Manager channel explicitly keeps651 a proposal, not an approved privacy decision.

## Decision and current boundaries

Keep read-only suggestions separate from action execution. Reuse existing policy/lifecycle owners after a reviewed candidate contract exists; do not invent a second miner or treat counts as confidence. No new scoring weights, cutoff, cooldown, dismissal retention, app identity rule or exception is selected here. Any later app integration, persistence or owner-policy change needs separate scope and authority. This plan neither adopts PR654 thresholds nor changes existing WatchSuggestions constants.

Read complete [Discover](../lib/services/discover.dart), [WatchSuggestions](../lib/services/watch_suggestions.dart), [context](../lib/services/watch_context.dart), [pipeline](../lib/services/watch_pipeline.dart), [policy](../lib/services/watch_policy.dart), [card](../lib/ui/watch_suggestion_card.dart), relevant main call sites, registry/privacy owners and unchanged fixtures. Bounded live open-PR search found [PR654/#561](https://github.com/shpalac/local-bluey/pull/654) and [PR653/#559](https://github.com/shpalac/local-bluey/pull/653) as upstream overlap, not duplicate562 delivery or accepted contracts. No source was copied or modified.

| Current source | Actual behavior | Not delivered by it |
| --- | --- | --- |
| Discover | Up to3 static suggestions from awake/routine/recent counts; local search/recents from existing stores, no screen read | Candidate ranking, repeated-pattern mining or durable dismissal |
| WatchSuggestions | Repeat vision text per normalized app/detail;3 repeats,3min gap,3/session;64 keys FIFO,512 detail/128 app code-unit limits; injected clock/never-app read | General routine candidates, weighted scoring, distinct-day recurrence or persistent per-candidate dismissal |
| Never-for-app | Existing SharedPreferences watch.suggestNeverApps; reads normalize through WatchPolicy; writer uses trim/lowercase; registry clear removes key | Verified encrypted activity storage, new retained-policy grant or uniform future candidate identity |
| Card/main | Quoted evidence read-only; Dismiss sets visible card null; Never awaits app preference then hides card | Durable per-candidate dismissal, action approval or safe execution. Existing callback completion/error/identity behavior is a separate review boundary |
| Lifecycle | Reset/dispose generation fences late preference results/errors; counters/keys reset, disposal joins stream close; current read failure propagates | Installed ordered suppression-write owner or proof of all restart/delete/race cases |

Existing WatchContext maps known app categories, returns null for unknown and uses0.8/0.65 based on title stability; confidentEnough0.6. These are source facts, not newly approved scoring semantics. WatchPolicy deny/allowlist is a heuristic with documented unknown-title/renamed-surface limits; quoted text, app names and fingerprints remain untrusted data. No suggestion can confer consent, override SafetyGate or authorize capture/transport.

## Upstream proposal, not adopted input

PR654 head `df30ce8740fff5dd8f8c5e4c58bb8c5d4a91213c` was OPEN when inspected. Its pure, unwired ObservedStep/PatternCandidate/PatternMiner proposal counts sequences and distinct UTC days, uses configurable defaults, separates context/gaps and caps steps. This is not current-main562 functionality, current acceptance or owner-approved thresholds. PR653 proposes an unwired WatchEvent normalizer; #555/#557 contracts remain unresolved. Coordinate adapters with their owners rather than extending their branches.

Source-review questions for the later candidate contract: displayed `context@sequence.join('>')` identity and internal NUL/separator tally key can collide when opaque labels contain delimiters; input-order ties preserve source position, not arbitrary permutation invariance. Proposed caps after building/sorting the input do not establish ingestion/allocation bounds; public candidate constructors and nested lists need a clear immutable snapshot contract. These are proposal review leads, not reproduced regressions or instructions to modify654. No new characterization test ran on that PR.

## Proposed typed boundaries

A future CandidateSnapshot should bind source revision, candidate schema/version, canonical app identifiers, context, ordered opaque step tokens, occurrence/distinct-day evidence and source completeness. Identity must be structurally encoded/versioned, not an ambiguous display string or raw screen text. Validate empty/oversized/control-character/delimiter/invalid numeric inputs without truncating different values into one identity. Store/display only authorized evidence; hashes do not make sensitive data harmless.

A future SuppressionSnapshot should distinguish explicit never-app choice, explicit candidate dismissal, cooldown observation, revision and verified/unavailable storage state. Ranking receives snapshots and an injected time source, not mutable globals or a network service. A Decision should distinguish eligible, suppressed(reason), invalid, prerequisite unavailable, cancelled/stale and failed; unknown storage/consent does not become permission. Counts and confidence use named units; numeric weights/caps and calendar-day basis remain decisions, not defaults chosen here.

Define a total comparator with explicit deterministic tie-breaks from reviewed identity. Dart List.sort is not stable when distinct values compare equal; reject non-finite/invalid scores before comparison. Same-instant UTC/local DateTimes compare chronologically, but calendar days are not Duration.inDays across DST. Require an explicit time/calendar contract and clock-rollback policy. No wall-clock cooldown or local/UTC day choice is adopted for new candidates.

| Proposed review stage | Deterministic fabricated fixtures before implementation |
| --- | --- |
| Validate/identify | Empty/control/delimiter tokens, repeated context, same display/different identity, oversized input and boundary cap; immutable outer/nested snapshots and mutation-after-input |
| Rank/deduplicate | Equal scores/order ties, shuffled same evidence, duplicated candidate vs legitimate context change, NaN/infinity, incomparable versions, missing prerequisite; no duplicate emission |
| Suppress | Exact cooldown boundary, clock reversal/forward jump, never-app normalized aliases, app choice changes, current and old dismissal revisions, duplicate concurrent emits; explicit reasons, no action |
| Persist/restart if separately authorized | Failed read/write/delete, acknowledged write before success, queued vs entered clear, restart with corrupt/unknown version, stale publish after clear; no silent state loss or new storage here |
| Lifetime/cancel | Held reads versus reset/dispose/clear, generation invalidation, joined owned work, no late UI/effect, cleanup failure explicit; original failure is not overwritten by retry |
| UI/evidence if separately assigned | Complete real rendered pixels for fabricated EN/HE/RTL/2x states, quoted hostile evidence remains data, specific app/candidate pinned before async choice; not native/device acceptance |

## Failure, privacy and rollback plan

Prefer one owner for suppression mutations and deletion if that implementation is later selected. Invalidate publication immediately on clear/revoke/dispose, serialize entered storage work, and return completion through actual write/delete rather than timers. A displayed Dismiss is not durable deletion; a successful preference future is not proof of complete registry/remote erasure. No retention/store/encryption or privacy policy is changed by this plan.

All experiments proposed here use fabricated content-free tokens, fake clocks and fake stores. No real user activity/capture/OCR/audio/log corpus, endpoint, model, filesystem persistence or native permission request was used for562. Keep existing SafetyGate and owner policy before any eventual runtime action; candidate production and a user's review never imply execution permission. Native/shared/provider/paid/self-hosted gates remain independent.

Rollback a future reviewed module by removing its wiring/adapter and preserving original receipt/schema history; separately verify suppression store behavior if one was authorized. Do not remove explicit never choices or erase prior failure evidence as cleanup. Future tests must retain honest prerequisite-unavailable and partial-failure results. This audit performs no rollback, new fixture, UI/baseline update, installed scoring engine or registry edit.

## Validation and primary sources

Fresh unchanged tests: `flutter test test/discover_test.dart test/watch_suggestions_test.dart test/watch_suggestions_lifecycle_test.dart test/watch_pipeline_test.dart test/watch_pipeline_lifecycle_test.dart test/watch_policy_test.dart --reporter expanded`:54 passed,0 new. Analyze clean; format273/0 changed. Generated SDK paths restored. These are existing synthetic contracts, not new562 regression coverage or native/persistence readiness. Exact-head static/test/linux/security/docs and manager APPROVED are still required for this plan PR.

- [Dart Comparator](https://api.dart.dev/dart-core/Comparator.html): total ordering and comparison sign contract.
- [List.sort](https://api.dart.dev/dart-core/List/sort.html): equal comparator values do not guarantee stable order.
- [List.unmodifiable](https://api.dart.dev/dart-core/List/List.unmodifiable.html): unmodifiable list boundary; nested mutable elements still need review.
- [DateTime](https://api.dart.dev/dart-core/DateTime-class.html): UTC/local instants and calendar/duration distinction.
- [DateTime.compareTo](https://api.dart.dev/dart-core/DateTime/compareTo.html): equivalent instant comparison independent of timezone representation.
- [DateTime.difference](https://api.dart.dev/dart-core/DateTime/difference.html): negative duration and daylight-saving/calendar limits.
