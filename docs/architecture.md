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
