# Mocked troubleshooting layout evidence

contact-sheet.png was rendered from reviewed code head 9692839cc11dc0a72dd8262d55a3236596afded0. EN/HE actual TroubleshootingScreen, 390x844, 200% text scale. Mocked HTTP 200 and unknown pairing results, not real server/device verification.

Command: DIAG_CAPTURE=/downloads/diag-317 /tmp/flutter-local/bin/flutter test test/troubleshooting_provider_layout_test.dart --reporter expanded

Pinned Flutter 3.47.6. Capture-only glyph override: DejaVuSans from /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf, MaterialIcons-Regular.otf from pinned SDK. Fixture fonts, not native font fidelity.

Inspected actual PNG: readable wrapped reachability-only title, expected RTL/icon alignment, no clipping/overlap. The evidence-only follow-up adds these files without changing code/tests; rerender identical.
