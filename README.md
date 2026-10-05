# Local Bluey

A blueberry character who lives on your iPhone under your Mac's screen and points at things with his own big cursor - now as a **Flutter app** for **macOS, iOS and Android** that can run **fully locally**. Forked from [rbrown101010/bluey-by-riley](https://github.com/rbrown101010/bluey-by-riley) and rebuilt: the hardcoded OpenAI Realtime WebSocket is gone, replaced by a modular brain that talks to local [Ollama](https://ollama.com) or any OpenAI-compatible API (OpenRouter, LocalAI, OpenCode…).

[![CI](https://github.com/shpalac/local-bluey/actions/workflows/ci.yml/badge.svg)](https://github.com/shpalac/local-bluey/actions/workflows/ci.yml)

**How it feels:** double tap his face to wake him. **Press and hold** to ask something; let go and he answers in a speech bubble. Ask "what's this?" and he points at whatever is under your mouse. Double tap again and he goes back to quietly following your pointer with his eyes.

**Using the computer:** when you ask, he can click, type, press shortcuts, scroll, drag, zoom into a region of the screen, wait for something to appear, and open apps and websites - with his own cursor, while your real pointer is put back where you left it. Needs Accessibility permission on the Mac.

## Status

- **Platforms today:** macOS (the host that sees and controls the computer) and iOS + Android (the phone clients). App roles are chosen by capability through a support matrix, not `Platform.isMacOS`, and platforms with no supported role (Linux, Windows) get an explicit unsupported screen instead of a broken UI. Computer control is Swift-only today, so a Linux or Windows host needs its own native implementation first.
- **Implemented:** Ollama and OpenAI-compatible brains, a settings screen, transcription and spoken answers over OpenAI-compatible HTTP endpoints, native tool calling, screenshot vision with zoom, a safety gate with confirmations and a kill switch, a local-only mode with screen-text redaction, a persistent action log and a data-egress report, unified data deletion and retention controls, conversation memory summaries, retry with backoff on dropped requests, onboarding with live permission checks, English/Hebrew UI with RTL and light/dark appearance, personality with moods and selectable characters, routines (user-defined macros), haptics on the phone client, empty/error/undo patterns, offline-first graceful degradation, optional biometric app lock, suggestions and search over past answers, and Mac-to-phone hold-to-talk over the local network.
- **Not done yet:** see the open [issues](https://github.com/shpalac/local-bluey/issues), including a real on-device wake-word spotter ([#79](https://github.com/shpalac/local-bluey/issues/79)), Android emulator CI ([#78](https://github.com/shpalac/local-bluey/issues/78)), real-device validation ([#15](https://github.com/shpalac/local-bluey/issues/15)) and an active safety/robustness hardening pass ([#107](https://github.com/shpalac/local-bluey/issues/107)-[#118](https://github.com/shpalac/local-bluey/issues/118)).

## Privacy: what stays local

Nothing is local unless you point it at a local endpoint. The brain, transcription and speech each use the endpoint you configure (the brain's URL by default for transcription and speech). With Ollama on your machine, nothing leaves it. If you configure a remote endpoint, your prompts, recorded audio and screenshot text are sent to that provider.

- **Local-only mode** (setting): refuses a brain endpoint that is not `localhost`, `127.0.0.1`, `::1` or a `.local` host.
- **Redaction:** screen text is scrubbed of email addresses, 16-digit card numbers and 9-digit numbers before it reaches the brain. This is pattern matching, so it is not a guarantee.
- **Egress report:** Settings > Data and privacy shows a verifiable record of what was sent, where and when, plus an offline self-test ([#58](https://github.com/shpalac/local-bluey/issues/58)).
- **API keys:** stored with `flutter_secure_storage` (Keychain on macOS and iOS), not in plain preferences.

## Safety

Tools that change your machine (`click`, `type_text`, `press_keys`, `scroll`, `drag`, `open_app`, `open_url`) ask for confirmation first, and `open_app` can be limited to an allowlist. A global kill switch cancels actions in flight. An optional biometric app lock (Touch ID / Face ID / device biometrics) can gate the app. A follow-up hardening pass on the safety gate and pairing channel is tracked in [#107](https://github.com/shpalac/local-bluey/issues/107)-[#118](https://github.com/shpalac/local-bluey/issues/118).

## Architecture

| Layer | Tech | What it does |
|---|---|---|
| UI | Flutter (Dart) | His face, gestures, speech bubble, menu-bar tray (macOS) |
| Brain | `lib/llm/` | `OllamaProvider` (local `/api/chat`) or `OpenAiCompatibleProvider` (any `/chat/completions` endpoint) |
| Tools | `lib/services/tool_executor.dart` | Runs the 14 tool calls (`look_at_screen`, `zoom_screen`, `wait`, `point_at`, `click`, `type_text`, …) the LLM emits |
| Native bridge | Flutter MethodChannel → Swift | ScreenCaptureKit + Vision OCR, Accessibility controls, CGEvent mouse/keyboard |
| Phone ↔ Mac | Bonjour (`nsd`) + newline-delimited JSON over TCP | The phone finds the Mac on the local network and mirrors his face |

The original Swift implementation is kept under `Mac/`, `iOS/` and `Shared/` as reference for the port.

## Run it

Requirements: Flutter (stable, Dart SDK ^3.13.5), a Mac for the desktop app, and either Ollama or an OpenAI-compatible endpoint. A phone is optional and needs to be on the same network as the Mac.

```bash
flutter pub get
flutter run -d macos   # the Mac app (grants Accessibility + Screen Recording on first use)
flutter run -d ios     # the iPhone app - it finds the Mac over Bonjour
flutter run -d android # the Android app - same discovery and hold-to-talk
```

No API keys in the repo: Ollama needs none; remote endpoints are configured in the app.

## Local data and retention

Everything the app stores lives on this device; Settings > Data and privacy lists each store with a clear button, and "Delete all local data" returns the app to first-run state (it does not touch your remote provider account data).

| Store | Where | Retention |
| --- | --- | --- |
| Conversation history + summary | Documents/conversation.json | Until deleted |
| Action log | Documents/actions.jsonl | 500 entries / 30 days |
| Egress record | Documents/egress.jsonl | 300 entries / 30 days |
| Routines | Documents/routines.json | Until deleted |
| Perf samples | Documents/perf.jsonl | Until deleted |
| Settings (API key in Keychain) | SharedPreferences + secure storage | Until deleted |
| Character, language, onboarding, safety, privacy, wake-word, app lock, haptics, notifications, theme, pairing/link keys | SharedPreferences | Until deleted |

## Development

- `flutter test` - unit + widget tests (tool-call parsing, executor math, protocol round-trips)
- `flutter test integration_test` - E2E: hold-to-talk → mock LLM → tool call through the MethodChannel
- CI (GitHub Actions, `macos-latest`): tests, analyze, format check, `flutter build macos`, `flutter build ios --no-codesign`, `flutter build apk --debug`, dependency vulnerability scan and secrets detection. Actions are pinned by SHA with least-privilege permissions, and failing jobs upload artifacts.

## OS integration (#91)

Deep links use the `localbluey://` scheme. Supported actions (validated in `lib/services/deep_links.dart`):

- `localbluey://wake` / `localbluey://sleep` - same wake/sleep path as the face gesture
- `localbluey://ask?text=<question>` - asks Bluey (text required)
- `localbluey://stop` - kill switch
- `localbluey://mute` - stops in-flight speech
- `localbluey://status` - shows current state

Deep links never run computer-control or other confirm-required actions silently; those stay behind the in-app safety gate (#19, #57).

The macOS tray offers quick actions: Ask Bluey (wake), Mute replies, Status, plus Show/Hide/Stop/Resume/Quit.

Platform limits: the global push-to-talk hotkey, iOS App Intents/Shortcuts, and widgets need native platform registration and are tracked as follow-up work.
