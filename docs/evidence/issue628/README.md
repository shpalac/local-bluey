# Fabricated settings connection failure

Inspected actual Flutter pixels in the existing settings screen, with a fabricated local refused connection. The failure code, summary, Detect/preset buttons and Details label are readable with no overlap. This is a crop of a 900x3000 Linux fixture using DejaVuSans; it is not native accessibility, narrow-device, RTL or every code/layout proof. Square missing icon glyphs are the test font, not a changed icon design.

Reproduce:
`CONNECTION_PIXELS=/tmp/connection.png flutter test test/connection_error_test.dart`

The same existing failure.code is displayed and emitted alone to Flutter diagnostics. Fixture verifies code presence and exclusion of target, raw socket details, port and fabricated secret from diagnostics. Existing raw Details remains opt-in and is not a privacy certificate. No persisted diagnostic store or new telemetry.
