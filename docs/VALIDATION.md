# Real-device validation (#15)

Static fixes already in this branch: NSLocalNetworkUsageDescription +
NSBonjourServices (_googly._tcp) on iOS and macOS, NSMicrophoneUsageDescription
on both. What remains needs a Mac and an iPhone on the same network.

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
3. Double-tap wake/sleep and confirm the Mac window reacts.
4. Hold to talk on the phone - confirm the Mac goes into listening mode
   (phone-side recording is a later slice; today's hold is a remote control).

## Known watch-items
- tray icon in dark menu bar
- window focus when waking from the tray
- TTS failure fallback shows text only
