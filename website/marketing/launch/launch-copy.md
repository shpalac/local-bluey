# Local Bluey launch drafts — not posted

These drafts deliberately say **developer preview** until the native-device testing is complete. Check project status, community rules and screenshots immediately before publishing.

## Developer project introduction (for GitHub Discussions or developer blog)

**Title:** Building a local-first AI desktop companion with Flutter and explicit approvals

I’m working on Local Bluey, an open-source experiment in making a Mac assistant feel like a small character rather than another chat tab. The macOS host has source-level screen capture, configurable AI providers, and a SafetyGate for computer-changing actions.

It can be configured to use a local Ollama brain. Speech transcription is a *separate* dependency, and native offline transcription is not shipped. iOS and Android are companion clients for the Mac, not mobile phone-control assistants.

This is an early developer project, **not a verified consumer release**. CI covers mocked paths, but end-to-end real-device behavior is not yet validated. I’d welcome feedback on native permissions, secure computer-control flows, and the contributor experience.

Repository: https://github.com/shpalac/local-bluey

Mac setup (source-only): https://shpalac.github.io/local-bluey/guides/mac-setup/

Validation status: https://github.com/shpalac/local-bluey/issues/15

## Local AI / Ollama learning post

**Title:** What it takes to make a local-first Mac assistant use Ollama

I’ve been exploring a Flutter Mac host where an on-screen character can answer questions about the desktop using a configured AI endpoint.

Ollama can be the local brain, but configuring a model is only part of the pipeline. Speech recognition and text-to-speech have different endpoint requirements. Local-only mode constrains supported endpoints to loopback; remote providers may receive screen or voice data if enabled.

The project is open source and still awaiting physical-device validation. I documented the configuration boundaries and current limitations here:

Ollama guide: https://shpalac.github.io/local-bluey/guides/ollama/

I’d particularly value reports on integration pitfalls or tests to add.

## Hacker News discussion draft — use only when demo/setup can be verified

**Title:** Show HN: Local Bluey — an open-source Mac AI companion with action approvals

I’m building an expressive desktop assistant for macOS with a Flutter UI, a configurable local-first AI brain and explicit approval for computer actions. You can inspect the code and source setup, but the device-validation checklist is still open.

The most interesting engineering work is in the separation between screen observation, action requests and user approval. I’d appreciate feedback from people building native desktop tooling.

Source: https://github.com/shpalac/local-bluey

**Publication gate:** Only use a Show HN framing if the project is genuinely usable/tryable under current HN rules. Otherwise publish an engineering writeup in an appropriate venue; never imply real-device testing is complete.

## Short project introduction

Local Bluey is an open-source AI companion for Mac with screen-awareness tools, configurable local AI and human-approved computer actions. Still in developer preview; physical-device validation is pending.

Browse the code: https://github.com/shpalac/local-bluey

## Publishing checklist

- [ ] Confirm links, screenshots and native-device claims against current repository state.
- [ ] Replace plain links with approved `npm run gtm:links` variants for the chosen channel if privacy policy allows.
- [ ] Read the target community's current self-promotion rules and disclose maintainer affiliation.
- [ ] Don't claim production readiness, quantified improvements, users, or endorsements.
- [ ] Record feedback and follow up on specific bugs; do not automate community posting.
