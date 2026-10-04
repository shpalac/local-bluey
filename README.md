# Local Bluey

A blueberry character who lives on your iPhone under your Mac's screen and points at things with his own big cursor - now as a **Flutter app** for **macOS and iOS** that can run **fully locally**. Forked from [rbrown101010/bluey-by-riley](https://github.com/rbrown101010/bluey-by-riley) and rebuilt: the hardcoded OpenAI Realtime WebSocket is gone, replaced by a modular brain that talks to local [Ollama](https://ollama.com) or any OpenAI-compatible API (OpenRouter, LocalAI, OpenCode…).

[![CI](https://github.com/shpalac/local-bluey/actions/workflows/ci.yml/badge.svg)](https://github.com/shpalac/local-bluey/actions/workflows/ci.yml)

**How it feels:** double tap his face to wake him. **Press and hold** to ask something; let go and he answers in a speech bubble. Ask "what's this?" and he points at whatever is under your mouse. Double tap again and he goes back to quietly following your pointer with his eyes.

**Using the computer:** when you ask, he can click, type, press shortcuts, scroll, drag, and open apps and websites - with his own cursor, while your real pointer is put back where you left it. Needs Accessibility permission on the Mac.

## Status

- **Platforms today:** macOS (the host that sees and controls the computer) and iOS (the phone client). There are no Android, Linux or Windows runners yet. Planned work is tracked in [#51](https://github.com/shpalac/local-bluey/issues/51), [#52](https://github.com/shpalac/local-bluey/issues/52), [#53](https://github.com/shpalac/local-bluey/issues/53) and [#54](https://github.com/shpalac/local-bluey/issues/54). Computer control is Swift-only today, so other platforms need their own implementation first.
- **Implemented:** Ollama and OpenAI-compatible brains, a settings screen, transcription and spoken answers over OpenAI-compatible HTTP endpoints, native tool calling, screenshot vision, a safety gate with confirmations and a kill switch, a local-only mode with screen-text redaction, onboarding, English/Hebrew UI with RTL, and Mac-to-phone hold-to-talk over the local network.
- **Not done yet:** see the open [issues](https://github.com/shpalac/local-bluey/issues), including a persistent action log ([#57](https://github.com/shpalac/local-bluey/issues/57)), a data-egress report ([#58](https://github.com/shpalac/local-bluey/issues/58)), personality ([#55](https://github.com/shpalac/local-bluey/issues/55)) and routines ([#56](https://github.com/shpalac/local-bluey/issues/56)).

## Privacy: what stays local

Nothing is local unless you point it at a local endpoint. The brain, transcription and speech each use the endpoint you configure (the brain's URL by default for transcription and speech). With Ollama on your machine, nothing leaves it. If you configure a remote endpoint, your prompts, recorded audio and screenshot text are sent to that provider.

- **Local-only mode** (setting): refuses a brain endpoint that is not `localhost`, `127.0.0.1`, `::1` or a `.local` host.
- **Redaction:** screen text is scrubbed of email addresses, 16-digit card numbers and 9-digit numbers before it reaches the brain. This is pattern matching, so it is not a guarantee.
- **API keys:** stored with `flutter_secure_storage` (Keychain on macOS and iOS), not in plain preferences.
- The local-only check looks at the brain endpoint (`baseUrl`). Whether a separate transcription or speech URL is also checked is not confirmed; a verifiable egress report is tracked in [#58](https://github.com/shpalac/local-bluey/issues/58).

## Safety

Tools that change your machine (`click`, `type_text`, `press_keys`, `scroll`, `drag`, `open_app`, `open_url`) ask for confirmation first, and `open_app` can be limited to an allowlist. A global kill switch cancels actions in flight.

## Architecture

| Layer | Tech | What it does |
|---|---|---|
| UI | Flutter (Dart) | His face, gestures, speech bubble, menu-bar tray (macOS) |
| Brain | `lib/llm/` | `OllamaProvider` (local `/api/chat`) or `OpenAiCompatibleProvider` (any `/chat/completions` endpoint) |
| Tools | `lib/services/tool_executor.dart` | Runs the 12 tool calls (`look_at_screen`, `point_at`, `click`, `type_text`, …) the LLM emits |
| Native bridge | Flutter MethodChannel → Swift | ScreenCaptureKit + Vision OCR, Accessibility controls, CGEvent mouse/keyboard |
| Phone ↔ Mac | Bonjour (`nsd`) + newline-delimited JSON over TCP | The iPhone finds the Mac on the local network and mirrors his face |

The original Swift implementation is kept under `Mac/`, `iOS/` and `Shared/` as reference for the port.

## Run it

Requirements: Flutter (stable, Dart SDK ^3.13.5), a Mac for the desktop app, and either Ollama or an OpenAI-compatible endpoint. An iPhone is optional and needs to be on the same network as the Mac.

```bash
flutter pub get
flutter run -d macos   # the Mac app (grants Accessibility + Screen Recording on first use)
flutter run -d ios     # the iPhone app - it finds the Mac over Bonjour
```

No API keys in the repo: Ollama needs none; remote endpoints are configured in the app.

## Development

- `flutter test` - unit + widget tests (tool-call parsing, executor math, protocol round-trips)
- `flutter test integration_test` - E2E: hold-to-talk → mock LLM → tool call through the MethodChannel
- CI (GitHub Actions, `macos-latest`): tests, analyze, `flutter build macos`, `flutter build ios --no-codesign`
