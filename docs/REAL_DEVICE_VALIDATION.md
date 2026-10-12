# Real-device validation protocol (#15)

Status: **NOT RUN**. These are instructions for a real Mac + iPhone + Android
device, not evidence of successful pairing or permissions.

## Test environment

- Mac model, macOS version, Flutter version, commit SHA:
- iPhone model and iOS version:
- Android model, OS version:
- Network: one trusted local network; VPN/firewall conditions:
- Reviewer/date:

Do not attach logs containing microphone audio, credentials, pairing codes,
raw screen content, network tokens or other private data.

## Preflight

Run these commands on a Mac with Flutter and Xcode installed:

```bash
flutter doctor -v
flutter devices
flutter pub get --enforce-lockfile
flutter analyze
flutter test test/bluey_character_test.dart
flutter test test/android_face_parity_test.dart
flutter build macos
flutter build ios --no-codesign
flutter build apk --debug
```

The FaceScreen-specific tests may be on feature branches until PRs #659/#660
are merged; do not treat missing files on main as completed tests.

## Physical Mac host

1. Start `flutter run -d macos` on a Mac, with both Accessibility and Screen
   Recording denied. Confirm the app requests only permissions needed for the
   user-initiated action and cannot bypass a denial.
2. Grant those permissions in System Settings and retry; capture timestamp and
   redacted UI evidence. Validate the real native permission state after
   restart, not just what the UI claims.
3. Revoke each permission during an active session. Verify observation and
   computer actions fail closed, with no crash or silent resumption.
4. Verify microphone prompts happen at the correct gesture/feature entry and
   that denial and re-grant are recoverable.
5. Verify the emergency stop/kill switch before any potentially destructive
   computer action.

## iPhone and Android clients

1. Launch a real iPhone client (`flutter run -d <ios-device-id>`) and the
   Android client (`flutter run -d <android-device-id>`) separately.
2. Confirm the Mac advertises its local service and is discoverable on the
   same LAN. On iOS check Local Network permission and Bonjour service
   declarations. Test denying and subsequently granting Local Network access.
3. Pair each phone with the Mac. Verify a user confirmation step, connection
   established, reconnect on Wi-Fi interruption, and safe behavior when the
   Mac is offline.
4. Deny, grant, revoke and re-grant microphone permission. Test hold-to-talk
   start and release, audible reply, cancellation and no unexpected recording.
5. Compare actual Bluey face appearance with the supplied device reference;
   check TalkBack/VoiceOver actions, landscape, RTL, reduced motion, themes
   and small displays. Link Android parity evidence to #660.
6. Confirm that no sensitive screen data or credentials are recorded in a
   bug report, screenshot or attachment.

## Required evidence to close #15

| Gate | Result (pass/fail/not run) | Hardware + OS | Evidence link |
| --- | --- | --- | --- |
| Mac Accessibility permission lifecycle | not run | | |
| Mac Screen Recording permission lifecycle | not run | | |
| Mac microphone prompt/revocation | not run | | |
| iOS Local Network / Bonjour pairing | not run | | |
| Android LAN pairing + mic lifecycle | not run | | |
| Kill switch on real Mac | not run | | |
| Reconnect/offline recovery | not run | | |
| iPhone and Android actual face rendering | not run | | |

No device pass can be inferred from simulator or mocked widget tests.
Close the issue only after a named reviewer attaches real-device evidence for
each required gate. Keep `blocked:device` until then.
