# Local Bluey

A blueberry character who lives on your iPhone under your Mac's screen and points at things with his own big cursor - now as a **cross-platform Flutter app** (macOS + iOS) that runs **fully locally**. Forked from [rbrown101010/bluey-by-riley](https://github.com/rbrown101010/bluey-by-riley) and rebuilt: the hardcoded OpenAI Realtime WebSocket is gone, replaced by a modular brain that talks to local [Ollama](https://ollama.com) or any OpenAI-compatible API (OpenRouter, LocalAI, OpenCode…).

[![CI](https://github.com/shpalac/local-bluey/actions/workflows/ci.yml/badge.svg)](https://github.com/shpalac/local-bluey/actions/workflows/ci.yml)

**How it feels:** double tap his face to wake him. **Press and hold** to ask something; let go and he answers in a speech bubble. Ask "what's this?" and he points at whatever is under your mouse. Double tap again and he goes back to quietly following your pointer with his eyes.

**Using the computer:** when you ask, he can click, type, press shortcuts, scroll, drag, and open apps and websites - with his own cursor, while your real pointer is put back where you left it. Needs Accessibility permission on the Mac.

## Architecture

| Layer | Tech | What it does |
|---|---|---|
| UI | Flutter (Dart) | His face, gestures, speech bubble, menu-bar tray |
| Brain | `lib/llm/` | `OllamaProvider` (local `/api/chat`) or `OpenAiCompatibleProvider` (any `/chat/completions` endpoint) |
| Tools | `lib/services/tool_executor.dart` | Runs the 12 tool calls (`look_at_screen`, `point_at`, `click`, `type_text`, …) the LLM emits |
| Native bridge | Flutter MethodChannel → Swift | ScreenCaptureKit + Vision OCR, Accessibility controls, CGEvent mouse/keyboard |
| Phone ↔ Mac | Bonjour (`nsd`) + newline-delimited JSON over TCP | The iPhone finds the Mac on the local network and mirrors his face |

The original Swift implementation is kept under `Mac/`, `iOS/` and `Shared/` as reference for the port.

## Run it

Requirements: Flutter (stable), a Mac for the desktop app, and either Ollama or an OpenAI-compatible endpoint.

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
