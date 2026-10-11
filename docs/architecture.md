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

## Known gaps

Tracked openly rather than claimed as done: Android/Linux ports
(#51-#54), integration lane on real hardware (#136), landing page (#126).

## Data flow example

"Open Mail" on the phone: phone sends `holdStart`/audio over the link ->
Mac transcribes -> brain returns `open_app(name: "mail")` -> safety gate
checks the allowlist and asks on the Mac screen -> user approves ->
native control launches Mail -> result goes back to the brain -> spoken
reply + face animation -> action and egress logs updated.
