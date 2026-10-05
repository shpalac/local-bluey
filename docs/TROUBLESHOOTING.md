# Troubleshooting

Organized by symptom. Every message the app can show has an entry below.
The in-app **Settings > Troubleshooting** screen runs the same checks live
and gives you copyable diagnostics.

## Bluey doesn't answer

**"Bluey's brain is unreachable. Face and local controls still work -
check the provider in Settings."**

- Cause: the brain endpoint (Ollama or OpenAI-compatible) didn't respond.
- Fix: Settings > Brain settings > run the connection test. For Ollama,
  make sure `ollama serve` is running and the model in Settings is
  installed (`ollama list`). For OpenAI-compatible, check the base URL
  ends with `/v1` and the API key is set.
- If the test passes but asking still fails, the model name is the usual
  suspect: it must match what the endpoint actually serves.

**A "Cloud provider active - data leaves this Mac" banner is showing.**

- Not an error: a warning that the configured brain is remote.
- To make it disappear, switch to a local provider or turn on Local-only
  mode (which refuses remote providers outright).

**A banner says Local-only mode refused the provider.**

- Cause: Local-only mode is on and the configured endpoint isn't local.
- Fix: point the brain at a local endpoint (e.g. Ollama on
  `http://localhost:11434`) or turn Local-only mode off in Settings.

## Voice problems

**"Voice input is unavailable right now - type your request instead."**

- Cause: the transcription endpoint failed or isn't configured.
- Fix: Settings > Transcription - check the base URL and model
  (`whisper-1`-compatible). The connection test covers the brain only;
  transcription has its own endpoint fields.

**"Voice replies are unavailable - answers will appear as text."**

- Cause: the speech (TTS) endpoint failed.
- Fix: Settings > Speech - check the base URL, model and voice. Answers
  keep arriving as text in the meantime.

**"No microphone permission."**

- Cause: macOS microphone permission is off for the app.
- Fix: System Settings > Privacy & Security > Microphone, enable the app,
  then hold to talk again.

## Pointing and clicking

**Bluey points or clicks the wrong place.**

- Cause: usually a stale screenshot or a changed window layout since he
  last looked.
- Fix: ask again - he takes a fresh look before acting. If it persists,
  check that accessibility permission is still granted (System Settings >
  Privacy & Security > Accessibility).

**Nothing happens when he should click or type.**

- Check the tray menu: if it says "Stopped (kill switch)", the kill switch
  is engaged - wake him again.
- If a confirmation appeared and timed out, the action was refused; ask
  again and confirm.

## Phone can't find the Mac

**"Looking for your Mac on the local network - will reconnect"**

- Cause: the phone and Mac aren't on the same network, or the Mac app's
  local network permission is off.
- Fix: same Wi-Fi for both, then iOS Settings > Privacy & Security >
  Local Network for the app. The link is plain TCP on the local network -
  captive portals and guest networks usually block it.

**Pairing prompt never appears, or appears for the wrong device.**

- The Mac shows one pairing prompt at a time. Dismiss the current one and
  retry from the phone. The key never travels over the wire: the phone
  answers a nonce with an HMAC, so a prompt you didn't trigger can be
  safely declined.

## Permissions

**A feature suddenly stopped after an update or reboot.**

- macOS occasionally drops grants. Check System Settings > Privacy &
  Security: Accessibility (point/click), Screen Recording (seeing your
  screen), Microphone (hold to talk), Local Network (phone link).

## Wake word

**Saying the wake word does nothing.**

- A real on-device wake-word spotter hasn't shipped yet (tracked as
  issue #79). Wake Bluey by double-tapping his face, from the tray menu,
  or with `localbluey://wake`.

## Kill switch

**"Stopped (kill switch)."**

- Everything in flight was cancelled, on purpose. Wake him from the tray
  or phone to continue.

## Status messages (not errors)

- "Awake and listening." - normal.
- "Sleeping - wake me from the tray or phone." - normal.
- "$tool (long-press to retry)" - a tool failed once; long-press the
  bubble to run it again.

## Still stuck?

Settings > Troubleshooting runs live diagnostics - copy them and follow
`docs/SUPPORT.md` for where to report.
