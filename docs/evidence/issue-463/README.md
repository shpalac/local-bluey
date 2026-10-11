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

Captured from commit a39c1ee7e38c6974dd1941cf7d7f0fbddc97db47 (the PR head before this README update; no source change since). Behavior is proven by the actual `test/onboarding_completion_test.dart` cases: repeat presses join one write, async false and thrown write failure show one safe error with no handoff and retry works, held write then disposal has no late callback, and a real preferences write persists done before handoff. The images prove only the rendered states above. Synthetic only.

The pixel test's 320 px at 2x variants run only with `TUTORIAL_PIXELS=1` because the default test font overflows at that size; the other variants run in the default suite as structural checks.
