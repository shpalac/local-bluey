# Architecture

Bluey is one Flutter codebase with two personalities: a desktop pet on
macOS and a remote control on iOS. Layers, top to bottom:

```
hold to talk
    |
    v
speech (lib/services/speech.dart, transcription.dart)
    |
    v
brain (lib/llm/brain.dart + providers: ollama, openai-compatible)
    |
    v
tool call --> safety gate (lib/services/safety_gate.dart)
    |             |  confirms risky tools, kill switch, allowlist
    v             v
tool executor (lib/services/tool_executor.dart)
    |
    v
host control (lib/services/host_control.dart abstraction,
              native_control.dart on macOS, fakes in tests)
    |
    v
result -> brain -> reply -> TTS (lib/services/tts via provider)
```

## Layers

- **UI** (`lib/ui/`): face screen, settings, onboarding, lock gate. The
  face is a widget driven by `FaceState`, not a platform view.
- **Brain / LLM** (`lib/llm/`): provider interface plus Ollama and
  OpenAI-compatible implementations. `Brain` owns conversation state and
  the tool-call loop.
- **Tool executor** (`lib/services/tool_executor.dart`): turns the
  model's tool calls into host-control operations, coerces sloppy
  argument types, and always answers the brain - never leaves a tool
  call hanging.
- **Safety gate** (`lib/services/safety_gate.dart`): every risky tool
  (click, type, keys, drag, scroll, open_app, open_url) requires a human
  yes unless the gate is deliberately off. Kill switch cancels in-flight
  work. Supports a time-boxed pause (#133).
- **Host control** (`lib/services/host_control.dart`): the abstraction
  that keeps Android/Linux ports possible (#51-#54). macOS implements it
  natively; tests use fakes.
- **Link protocol** (`lib/link/`): newline-delimited JSON packets over a
  local TCP socket, discovered via Bonjour (`_googly._tcp`). Pairing is
  approved on the Mac; authentication is HMAC challenge-response so the
  shared key crosses the wire once at pairing (#111). The phone's remote
  commands are a small allowlist (wake, sleep, hold-to-talk).
- **Privacy** (`lib/services/privacy_guard.dart`,
  `egress_monitor.dart`, `data_registry.dart`): local-only mode gates
  every endpoint (strict loopback check, `.local` names no longer count,
  #121); everything that leaves the device is recorded in the egress
  log; the data registry lists what lives where on disk.
- **Action log** (`lib/services/action_log.dart`): bounded retained record of
  executed actions, one run id per brain turn (#57). Startup recovery and
  record/load/delete are ordered; unknown/corrupt disk history is not overwritten.

## Capture monitor (BLU-007)

`lib/services/capture_monitor.dart` sits on top of `ScreenWatch`. It exposes
an indicator (off, active, paused), pause and resume, refusal counters by
reason (paused, not allowed, hard denied, private window, locked), an
immediate `stop`, and `attachLock`, which stops capture when a lock signal
says locked. It never starts a session: `resume` only lifts a pause inside a
running session, and ending the session forgets the pause. State is in memory
only, so after a restart the indicator is off. The counters are integers; no
app names, titles or screen content are recorded. It is not wired into the
app yet and makes no privacy or retention decision.

`runIfAllowed` fences each request by a monitor epoch and the `ScreenWatch`
generation captured before its first gate: stop, restart, pause, resume or
dispose in between refuses the request or drops its result. Pausing during a
running operation drops that result but cannot cancel the operation itself.
Refusal reasons are best effort: the watch is asked twice, and a denial by the
second ask is counted as not allowed without a finer reason. After `dispose`,
`attachLock` and `resetRefusals` do nothing (counts are left as they were) and
`stop` still stops without notifying. This is partial, unwired groundwork for BLU-007: BLU-001 is not
resolved and nothing here claims the full issue.

## Pattern miner (BLU-008)

`lib/services/pattern_miner.dart` finds repeated step sequences in a list of
`ObservedStep`s (an opaque fingerprint, a time and an optional context). It is
pure Dart: no I/O, no clock, no randomness, nothing kept between calls, and it
is not wired into the app. A sequence is reported only when it reaches both the
occurrence and the distinct-UTC-day thresholds, so a burst on one day never
qualifies. Runs split on a long pause or a context change, sequences never span
contexts, a shorter sequence with the same counts as a longer one that contains
it is dropped, and the result order is fixed. Steps are ordered by time and
equal-time steps keep the caller's input order, so that order can change the
result. Occurrences are counted with overlap and belong to the UTC day of their
first step. At most `maxInputSteps` input steps are visited per call, valid or not (one more
throws with a count only, so iteration is always finite). Steps with an empty or
too long fingerprint or a too long context (`maxContextLength`) are dropped, and
only the most recent `maxSteps` of the rest are mined. The limits are
engineering input safeguards, not product thresholds. Invalid configuration throws. This is partial, unwired groundwork for
BLU-008: BLU-004/006 are not merged and nothing here claims the full issue. It reads no screen content and makes no suggestion or policy decision.

## Suggestion ranker (BLU-009 groundwork)

`lib/services/suggestion_ranker.dart` ranks, de-duplicates and suppresses
`PatternCandidate`s. It is pure Dart and not wired into the app: no I/O, no
clock (the caller passes `now`), nothing kept between calls, and it never
acts. Every candidate comes back with a verdict (rankEligible, duplicate,
dismissed, neverContext, invalid or overCap). Order is total: distinct days,
then occurrences, then sequence length, then candidate id, so input order does
not matter. Those counts are evidence, not a confidence value. Rank-eligible
only means not suppressed here: this module checks no allowlist, privacy or
consent state, and callers must apply those independent gates before showing
anything. Candidate input is bounded: a required `maxCandidates` limit is
enforced while iterating, before any sort, and one more candidate throws
`CandidateLimitExceeded` (limit only, no content), so an endless or huge
iterable cannot hang or exhaust memory. Cooldown, the display cap and that
limit are required constructor arguments; this module picks no
numbers. A dismissal hides the exact candidate id until the cooldown has
passed, and a dismissal dated after `now` (clock moved back) stays hidden. A
never-context choice hides every candidate in that exact context.

Suppression state is a caller-supplied in-memory `SuppressionSnapshot` (copied
and immutable). This module does not store, load or delete anything: who
persists dismissals, where and for how long is a separate owner decision, and
unavailable state must be passed as a failure, never as an empty snapshot
(missing suppression state is fail-closed: the caller must not call `rank`).
This is partial groundwork for BLU-009 (#562): no persistence, no UI, no app
wiring, no restart or deletion behavior, and no claim that ADR-001 or any
retention policy is adopted.

## Action events (BLU-006)

`lib/services/action_events.dart` maps `WatchEvent`s from `WatchPipeline` into
`ActionEvent`s: a stable kind (app activated, screen changed, screen
described), the allowlisted app, the source time, a fixed per-kind confidence,
a sequence number and a session id. It is pure Dart and in memory only. It is
not wired into the app, persists nothing, keeps no window titles or vision
text, and records no keystrokes. The allowlist is asked again per event and a
throwing check drops the event. Duplicates of the same kind and app inside a
debounce window collapse even when other events arrive between them (per-key
debounce, hard-capped to `maxEvents` tracked keys: past the cap the least recently accepted key is evicted and is no longer debounced), invalid configuration is rejected, timestamps must stay monotonic even across `endSession` (an older event is dropped in the new session; only `clear` forgets the last time), a silence longer than the session gap or a call to
`endSession` starts a new session, and the retained list is capped. It makes
no privacy or retention decision; those stay with the blocked policy items.
This is partial, unwired groundwork for BLU-006: BLU-002/003 are not merged
and nothing here claims the full issue.

## Retention purge (BLU-005)

`lib/services/retention_purge.dart` is a scoped purge over a list of stores. It
shows each store's declared retention text and clears only stores the caller
classified as activity or cache. Anything else, including every store that is
not classified, is protected and refused. The guarantee that routines and
settings are untouched is conditional on a trusted caller: a caller that
classifies such a store as activity or cache can purge it, because this module
makes no classification or product-default choice. A store that throws is reported by
exception type only and the rest still run, a second purge while one is running
is refused as busy, and repeated ids are cleared once. It is pure Dart, holds
no data, is not wired into the app and has no UI. It picks no retention period,
no default and no classification of the existing stores: those wait for the
separate owner policy decision (ADR-001 adoption is not claimed here). This is partial, unwired groundwork for BLU-005: nothing
here claims the settings UI or the full issue.

## Known gaps

Tracked openly rather than claimed as done: Android/Linux ports
(#51-#54), integration lane on real hardware (#136), landing page (#126).

## Data flow example

"Open Mail" on the phone: phone sends `holdStart`/audio over the link ->
Mac transcribes -> brain returns `open_app(name: "mail")` -> safety gate
checks the allowlist and asks on the Mac screen -> user approves ->
native control launches Mail -> result goes back to the brain -> spoken
reply + face animation -> action and egress logs updated.

## Proactive observation sensitive-content gate (BLU-003, pending PR)

[BLU-003 implementation and risk register](BLU_003_SENSITIVE_CONTENT_GATE.md):
`ScreenWatch` checks explicit session consent and local-only mode;
`WatchPolicy` enforces user allowlisting and a hard denylist;
`SensitiveContentGate` then rejects unknown/private/sensitive window metadata
**before** the `WatchPipeline` processes frames or events. `WatchVision`
(pure fixtures only; production vision is wired off and fails closed) requires
non-empty OCR verified against the exact captured image and rechecks
foreground identity before it would send a picture to the configured provider.

**Scope and limitations:** This is proactive watch only, not every explicit
conversational screenshot tool. Keyword/OCR checks are best effort and native
window-switch races remain for physical validation. No new persistence or
unattended capture is enabled. The current `SafetyGate` remains in force.
