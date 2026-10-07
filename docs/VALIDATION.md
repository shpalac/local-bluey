# Real-device validation (#15)

Nothing below has been run on hardware. The full walkthrough lives further down
this page; this section records what has been fixed so far.

## Fixed without a device

`ios/Runner/Info.plist` declared NSMicrophoneUsageDescription,
NSLocalNetworkUsageDescription and NSBonjourServices one level too deep -
nested inside the innermost `UIApplicationSceneManifest` scene dict instead of
being direct children of the root dict. The file still parsed, so
`plutil -lint` and `flutter build ios` both passed and nothing caught it, but
iOS never saw the keys: no microphone prompt on first hold-to-talk, no
local-network prompt, and no Bonjour service type, so the iPhone could not
discover the Mac at all.

The keys are now at the top level, and `test/privacy_plists_test.dart` fails
CI if they move back down or out of alignment with `kServiceType`.
`macos/Runner/Info.plist` and the legacy native plists were checked and were
already correct.

## Mac
1. `flutter run -d macos`
2. Grant Accessibility when prompted (the banner has the shortcut).
3. Grant microphone when first holding to talk.
4. Open settings (gear), pick the provider, save, use Test connection.
5. Hold to talk: "what's on my screen?" - expect transcription in the bubble,
   the thinking face, a spoken reply, and TTS audio.

## iPhone
1. `flutter run -d ios` on a real device (Bonjour fails on the simulator for
   local network discovery unless the Mac is on the same host).
2. Accept the local-network permission prompt; the Mac's face should appear.
   With the plist bug above there was no prompt and no Mac - that is the
   first thing to check if the list is empty.
3. Double-tap wake/sleep and confirm the Mac window reacts.
4. Hold to talk on the phone - confirm the Mac goes into listening mode
   (phone-side recording is a later slice; today's hold is a remote control).
5. Reinstall the app and confirm it can pair again (#112).

## Known watch-items
- tray icon in dark menu bar
- window focus when waking from the tray
- TTS failure fallback shows text only

## Full run script (#125)

One run on a named Mac and iPhone, recorded once. Nothing below has been run
on real hardware yet.

Every issue referenced here is closed, so these are regression checks rather
than open bugs: the code is fixed but never confirmed on a device, which is
what the README means by "nothing has been verified on real hardware". File a
new issue for any step that fails.

### Setup (record before you start)
- Mac model and macOS version
- iPhone model and iOS version
- Flutter version and app build or commit
- LLM provider and model
- Both devices on the same Wi-Fi network

### Mac
1. First launch: onboarding shows live permission status. Grant Accessibility,
   Screen Recording and Microphone.
2. Hold the face or Space and ask "what's on my screen?". Expect the
   transcript, the thinking face, an answer and TTS. Check that no recording
   file is left in the temp directory (#116).
3. Safety: ask Bluey to click and type. The confirm dialog must show the full
   text and Return (#108). Press Stop during the dialog and during a request
   (#107).
4. Turn local-only on with a remote transcription or TTS URL. Requests must be
   refused (#120).
5. Quit and relaunch. Settings persist, and delete-all data works (#83).

### iPhone
6. Fresh install: the phone finds the Mac, the Mac shows a pairing prompt, and
   the key is stored. Since #111 the key is handed over once and later
   connects prove it with an HMAC nonce challenge, so no key should ever cross
   the link in cleartext again.
7. Hold to talk: audio reaches the Mac and the answer shows on the phone.
   Release quickly (a tap) and confirm the mic indicator goes off (#117).
8. Turn Wi-Fi off for 20 seconds. Expect an offline state, an automatic
   reconnect and no ghost entries on the Mac (#113, #114).
9. With two Macs available, choose a different Mac (#114).
10. Reinstall the iPhone app. Check that it can pair again (#112).

### Capture
- Pass or fail for each step, with screenshots, device logs and any crash.
- File a new issue for each failure and link it from #15.

### Done when
- A completed run is posted on #15 with the setup versions above, and every
  failing step has an issue.
