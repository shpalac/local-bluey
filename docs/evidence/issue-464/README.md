# Issue 464 evidence: Settings tutorial replay tile

Synthetic widget evidence only. No device, native or storage-durability claim.

## Harness

- Test: `test/settings_tutorial_replay_pixels_test.dart`, actual `SettingsScreen` with an actual `TutorialController` over a held/failing in-memory `TutorialDoneStore`.
- Regenerate: `TUTORIAL_PIXELS=1 FLUTTER_ROOT=<flutter sdk> flutter test test/settings_tutorial_replay_pixels_test.dart`. Without the variable the same test runs the structural assertions (tile at least 48 px tall) and writes nothing.
- Readiness is observed (the test pumps until the Settings list exists), not slept.
- Fonts: Roboto from `assets/fonts`, Noto Sans Hebrew from `/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf`, Material icons from the SDK.
- Dimensions: widths 320 and 1000 logical px (height 900, device pixel ratio 1), text scale 1.0 and 2.0, English and Hebrew (RTL).
- File name: `<width>-<scale>-<en|he>-<state>.png`.

## States (32 images)

- `pending`: reset held, subtitle "Resetting..."
- `error`: reset failed, generic notice snackbar plus the tile subtitle that offers retry
- `retry-pending`: explicit retry started, held again
- `success`: retry settled, success notice

## Scope limits

Captured from the PR head named in the PR thread. The screenshots show the Settings list scrolled to the replay tile; other rows use the default Material look. Behavior (joined taps, reentrant tap, replaced owner, disposal, sync and async failure, retry) is proven by `test/settings_tutorial_replay_test.dart`, not by the images.
