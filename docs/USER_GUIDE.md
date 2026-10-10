# Local Bluey - User Guide

Everything here describes the app as it ships today. If something on your
screen looks different, the app is right and this guide is stale - tell us
via `docs/SUPPORT.md`.

## Meet Bluey

Bluey lives on your Mac as a small face that follows your pointer with his
eyes. He can see your screen, hear you while you hold to talk, and point,
click and type for you - always with a confirmation before he changes
anything.

![Bluey listening](screenshots/face-listening-light.png)

## Gestures

- **Double tap his face** - wake him up. Double tap again and he goes back
  to sleep, quietly following your pointer.
- **Press and hold** - ask something. Keep holding while you speak; let go
  and he answers in a speech bubble (and out loud, if speech is set up).
- **Ask "what's this?"** - he points at whatever is under your mouse.

![Pointing](previews/pointer-comet.gif)

The same actions exist as deep links, so you can wire them into Shortcuts:
`localbluey://wake`, `localbluey://sleep`, `localbluey://ask?text=...`,
`localbluey://stop`, `localbluey://mute`, `localbluey://status`.

## The voice flow, step by step

1. Press and hold the face. He shows *Listening*.
2. Speak. Let go.
3. Your words go to the transcription endpoint, then to the brain.
4. The answer lands in the bubble and is spoken back.

If anything in that chain fails you get the error in the bubble, not
silence - see `docs/TROUBLESHOOTING.md`.

## What Bluey can do on your machine

Read-only tools run straight away:

- **look_at_screen / zoom_screen** - takes a screenshot (optionally zoomed)
  so he can see.
- **point_at / point_at_spot / stop_pointing** - shows you where something
  is.
- **wait** - pauses between steps.
- **go_to_sleep** - puts him back to sleep.

Tools that change your machine **always ask first**:

- **click**, **type_text**, **press_keys**, **scroll**, **drag**
- **open_app** (can be limited to an allowlist you set in Settings)
- **open_url**

The confirmation shows exactly what he wants to do before it happens. You
can pause these confirmations for 15 minutes from Settings, or turn the
gate off entirely after a warning.

## The kill switch

`localbluey://stop` cancels every action in flight immediately. Use it the
moment Bluey starts doing something you didn't mean.

## Privacy controls

- **Local-only mode** (Settings): refuses any brain, transcription or speech
  endpoint that is not on this machine (loopback addresses only). The toggle
  itself does not edit screenshots or text.
- **Screen-text scrubbing** (separate from the toggle): before screen text
  reaches the brain, email addresses, 16-digit card-shaped numbers and
  9-digit numbers are replaced with `[redacted]`. Passwords and tokens are
  not recognised as such, and images are never edited. If the text matches
  one of those patterns, the screenshot and any zoom crop of that screen are
  withheld instead. A zoom crop is also withheld when its text could not be
  checked. This is pattern matching and can miss secrets; see the README
  privacy section for the exact limits.
- **Data-egress report**: every outbound request is counted, per endpoint,
  so you can see exactly what left the machine.
- **Action log**: a persistent record of what Bluey did.
- **Data deletion & retention**: Settings > data privacy clears stored data
  by category.
- **Biometric app lock**: require Touch ID / Face ID to open the app.

## The phone remote

Pair your iPhone to hold-to-talk from across the room. Pairing shows one
prompt at a time on the Mac and never sends the pairing key over the wire
(the phone proves it with an HMAC of a nonce). The link is plain TCP on
your local network - use it on networks you trust.

## Making him yours

- **Characters and moods** - pick how he looks and reacts.
- **Language** - English or Hebrew UI (full RTL), separate speech language
  for transcription (auto-detect, Hebrew or English).
- **Appearance** - light, dark, or system.
- **Routines** - record a sequence once, replay it as a macro, share it as
  JSON.
- **Suggestions and search** - find past answers and re-ask in one tap.

## Settings > Help

- **User guide** - this document.
- **Troubleshooting** - live checks with copyable diagnostics, plus
  `docs/TROUBLESHOOTING.md` for symptom-by-symptom fixes.
- **Permissions in use** - what Bluey uses (microphone for hold-to-talk on
  the phone remote, local network for finding your Mac) and where to revoke
  them. macOS permissions for the Mac app itself (accessibility, screen
  recording, microphone) are managed in System Settings > Privacy &
  Security.
