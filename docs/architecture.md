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

## Known gaps

Tracked openly rather than claimed as done: Android/Linux ports
(#51-#54), integration lane on real hardware (#136), landing page (#126).

## Data flow example

"Open Mail" on the phone: phone sends `holdStart`/audio over the link ->
Mac transcribes -> brain returns `open_app(name: "mail")` -> safety gate
checks the allowlist and asks on the Mac screen -> user approves ->
native control launches Mail -> result goes back to the brain -> spoken
reply + face animation -> action and egress logs updated.
