# Real-device validation (#15)

Nothing below has been run on hardware. The scripted walkthrough lives in
# #125; this page is the short version plus what has been fixed so far.

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
