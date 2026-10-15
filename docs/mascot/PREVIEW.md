# Joyful Bluey mascot preview evidence

The default `FaceScreen` now draws a distinctive round blue bird with wings,
cyan eyes, an orange beak, a pale belly and a star-shaped chest feather. It
uses Flutter's platform-independent Canvas, with no network requests or
third-party animation runtime.

Animation is tied to the existing finite `FaceScreen` controller (breathing,
wave and blink), speech level (mouth shape), mood (smile, eyes), gaze, wake
state and accessibility reduce-motion preference.

Run `flutter test test/joyful_mascot_test.dart` for behavioral coverage.
The [mascot preview workflow](../../.github/workflows/mascot-preview.yml)
runs the same Flutter widget-render capture at platform-specific logical
viewport sizes on GitHub-hosted macOS and Linux runners and uploads four
separately named screenshots.

**Evidence distinction:** these PNGs are Flutter widget renders sized for
macOS, Linux, iOS and Android. They are not evidence of an app running on
a physical device, Android emulator or iOS simulator. Native builds are
checked in the repository's existing CI jobs; real-device validation remains
an independent acceptance requirement.

Existing screenshot goldens intentionally use the old face artwork as
historical baselines until they can be reviewed and rebaselined separately.
Do not use them to advertise the new mascot.
