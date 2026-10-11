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

## Egress record

**I cannot find the report or offline self-test in Settings.**

- Settings > Data and privacy lists the egress storage category and clear
  control, not a live report or self-test button. Do not use the brain
  connection test as an offline or STT readiness check.
- The internal self-test checks legacy brain settings and retained hosts,
  not separate active STT settings. Native transcription is not installed;
  an empty result does not prove usable offline voice or zero traffic.

**The history is empty, unavailable/incomplete, or the amount looks wrong.**

- Missing history is not proof that nothing was sent. Only selected callers
  record metadata; streams and the Diagnostics probe are not recorded.
- Amounts mix brain JSON/speech-text character counts, transcription input
  bytes and zero-amount checks. They omit request wrapping/headers and are
  not network byte totals or delivery receipts. Failed attempts may have
  rows or none; a Settings test may produce separate caller rows.
- Unknown or `.local` hosts are not confirmed on-device. Classification
  uses no DNS; a local service may forward data.
- Unreadable/partly corrupt history is preserved rather than overwritten.
  Clear only if you intend to delete retained history. A failed clear does
  not confirm deletion; successful clear waits for older storage work,
  not traffic, physical erasure or new records. No report/export or manual
  file-editing workaround is offered.
- See [record and self-test limits](USER_GUIDE.md#egress-record-and-self-test-limits).

## Voice problems

**"Voice input is unavailable right now - type your request instead."**

- This text is degraded-mode metadata, not a working typed-request
  workflow. The current app has no typed-request form wired to dispatch;
  configuration fields and parsed ask URLs do not submit questions.
- Voice may fail because saved STT configuration is missing, its endpoint
  or model is unavailable, or native transcription was selected. Native
  transcription is still a not-installed placeholder.
- HTTP STT uses a separate explicit saved endpoint/model/key. First STT
  load copies saved legacy transcription fields once; it does not use the
  general brain URL as a missing endpoint. After migration, edits to the
  current Settings transcription form change only legacy fields, not
  active STT settings. No supported provider picker or complete active-STT
  configuration workflow is exposed there today. Do not treat those edits
  as a verified fix; no manual preference-editing workaround is offered.
- The connection test covers the brain only. First-success STT readiness
  checks configuration, not server reachability, credentials, model or
  language support. A local brain or installed model-store asset alone
  does not make STT ready.
- Double-tap the face or choose tray **Ask Bluey** to wake Bluey; neither
  supplies transcription or a typed question. Voice asking remains
  unavailable until usable STT configuration and service are available.
  See [configuration limits](USER_GUIDE.md#transcription-configuration-and-limits)
  and the [source audit](STT_READINESS_REMAINDER.md).

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
  is engaged - use **Resume** in the Mac tray. Waking the face does not
  reset the kill switch.
- If a confirmation appeared and timed out, the action was refused; ask
  again and confirm.

## Phone can't find the Mac

**"Looking for your Mac on the local network - will reconnect"**

- Cause: the phone and Mac aren't on the same network, or the Mac app's
  local network permission is off.
- Fix: same Wi-Fi for both, then iOS Settings > Privacy & Security >
  Local Network for the app. The link is plain TCP on the local network -
  captive portals and guest networks usually block it.

**No local-network prompt appears at all, and no Mac ever shows up.**

- Cause: the app did not declare the permission. iOS only offers the prompt
  when `NSLocalNetworkUsageDescription` and `NSBonjourServices` are direct
  children of the root `Info.plist` dict - nest them one level too deep and
  iOS drops them silently while the file still lints clean. This is what
  #15 was; `test/privacy_plists_test.dart` now guards it.
- Fix: `flutter test test/privacy_plists_test.dart`, then reinstall the app
  (a pending local-network decision is not re-prompted by a rebuild).

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
  issue #79). Wake Bluey by double-tapping his face or choosing **Ask
  Bluey** in the Mac tray. `localbluey://wake` is a parser example only:
  the current app has no incoming URL registration or consumer/dispatch.
  It is not a wake workaround or working Shortcut.

## Kill switch

**"Stopped (kill switch)."**

- The safety kill switch is engaged. Use **Resume** in the Mac tray to
  lift it; waking from the face or phone is separate. Stop invalidates
  request/tool generations, not every entered native/network effect.
  Screen-watch Stop and speech Mute are separate controls. An incoming
  `localbluey://stop` URL does not operate this switch.

## Status messages (not errors)

- "Awake and listening." - normal.
- "Sleeping - wake me from the tray or phone." - normal.
- "$tool (long-press to retry)" - a tool failed once; long-press the
  bubble to run it again.

## Still stuck?

Settings > Troubleshooting runs live diagnostics - copy them and follow
`docs/SUPPORT.md` for where to report.
