# Android face parity validation (#660)

Android renders the same Flutter FaceScreen and BlueyCharacter components as
the Mac host and iOS Flutter client (#659). The older SwiftUI iPhone animation
is the reference design, not the renderer Android runs.

## Automated Flutter geometry checks

Run `flutter test test/android_face_parity_test.dart`.

The fixtures exercise 320x568, 412x915, 915x412 and 800x1280 logical viewport
sizes under Android Material theming. They check bounded square artwork, RTL,
large type, reduced motion and absence of rendering exceptions.

**A passing widget test is not physical Android validation.**

## Acceptance evidence still required

1. Build with `flutter build apk --debug` and run the app on a physical
   Android device; record model, OS version and commit SHA.
2. Capture device screenshots in portrait, landscape, light and dark.
3. Compare against the owner's iPhone/Mac artwork: round gradient body,
   eyebrows, blinks/eyelids, cheeks, mouth and top tuft.
4. Verify gaze and every mood, speech-level animation, double-tap wake,
   hold-to-talk start/end, and accessibility custom actions using TalkBack.
5. Turn on Android **Remove animations**; confirm no perpetual motion.
6. Check a low-end Android device for smooth rendering and no clipping.
7. Attach sanitized screenshots and device results to #660 before closure.

Visual similarities cannot be claimed from app-icon assets or widget tests alone.
