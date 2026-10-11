# Issue 463 evidence: onboarding completion summary

Synthetic widget evidence only. No device, native or storage-durability claim.

## Harness

- Test: `test/onboarding_completion_pixels_test.dart`, the actual `OnboardingScreen` summary step over a held/failing in-memory completion store and a fake permission checker.
- Regenerate: `TUTORIAL_PIXELS=1 FLUTTER_ROOT=<flutter sdk> flutter test test/onboarding_completion_pixels_test.dart`. Without the variable the test runs structural assertions and writes nothing.
- Readiness is observed (the test pumps until the expected widgets exist), not slept. The real-prefs test in `test/onboarding_completion_test.dart` polls until the persisted event appears.
- Fonts: Roboto from `assets/fonts`, Noto Sans Hebrew from `/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf`, Material icons from the SDK.
- Dimensions: widths 320 and 1000 logical px (height 900, device pixel ratio 1), text scale 1.0 and 2.0, English and Hebrew (RTL).
- File name: `<width>-<scale>-<en|he>-<state>.png`.

## States (32 images)

- `pending`: completion write held
- `error`: write failed, generic user-safe notice with retry and back actions
- `retry-pending`: explicit retry started, held again
- `success`: retry settled, handoff in progress (actions disabled)

## Scope limits

Captured from the PR head named in the PR thread. Behavior (held write, disposal, stale owner, sync and async failure, retry, real prefs) is proven by the tests, not by the images. Synthetic only.
