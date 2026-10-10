# Synthetic home-card evidence (#319)

Contact sheet: actual Flutter widget renders at 320 logical pixels, 2x text scale, EN and HE/RTL. Columns: permission Fix failure feedback, repeated suggestion with long app name and quoted hostile data, active banner at 65:00. No real screen/user data, native permission request or hardware capture.

Captured from `test/home_status_cards_test.dart` via CARDS_CAPTURE. The fixture loads DejaVuSans plus the pinned Flutter MaterialIcons font only for capture, not production. Optional CARDS_FONT/CARDS_ICONS override their filesystem paths. Production assets, fonts and #279 harness are unchanged. Pixels were inspected for wrapping, visibility and clipping; this is fixture layout evidence, not macOS native/VoiceOver certification.

The quoted sentence in the suggestion is synthetic untrusted display data, never an instruction.

This one bounded image exists for PR review and can be dropped before merge if preferred.
