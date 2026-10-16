# BLU-032 Rive fallback and reduced-motion contract

The app does not bundle a Rive runtime or assets. Every `FaceRenderer.rive`
request intentionally resolves to the licensed native Flutter character
painter. Until an asset license and supported runtime are reviewed, there
is no alternate animation backend, no network access and no new asset
distribution.

`BlueyCharacter` now honors `MediaQuery.disableAnimations` directly
by passing a fixed zero phase to either native painter. This applies
even outside `FaceScreen`, preserving reduced-motion behavior when a
parent passes an active animation phase. Static mood, speech and gaze
inputs remain available.

Run `flutter test test/rive_reduced_motion_fallback_test.dart` alongside
the renderer fallback and character tests. The native fallback can be
rolled back without storage migrations. A genuine Rive implementation,
golden approval, asset provenance review and native accessibility/RTL
validation are still needed for full feasibility acceptance.
