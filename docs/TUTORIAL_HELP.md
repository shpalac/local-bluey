# First-steps tutorial help

This page describes the first-steps tutorial card, how to skip or replay it, and what its error messages mean. It is based on the current source and existing tests, and it only claims what they show.

The tutorial is a short guided demo. It is not a permission check and not a readiness check. Finishing or skipping it says nothing about whether permissions, speech or a brain are set up.

## What the card is

The card is titled **First steps** and appears at the top of the Mac main screen. It shows one instruction at a time with a step counter such as 1/3:

1. "Double-tap Bluey's face to wake him." The step finishes when Bluey really wakes.
2. Press and hold, ask the suggested request, then let go. The step finishes when the answer arrives.
3. "Now ask him to point at something - watch the cursor fly." The step finishes when Bluey really points.

Steps finish on the real event, not on a button press. If pointing is not available on this Mac, the tutorial has two steps and ends after the first answer.

## Skip

Press **Skip tutorial** at any step. The tutorial ends, the card disappears, and the choice is saved on this device so it does not come back at the next start.

If the save fails, the card stays and says "Could not save tutorial completion. Try again." The button now reads **Retry**. Press it to try the save again. While saving, the button reads "Saving...". Nothing retries on its own. Finishing the last step has the same save, and a failure there shows the same message and **Retry**.

## Replay

Open Settings and press **Replay first-steps tutorial** (subtitle: "Wake, ask, point - the guided demo.").

- While it works the subtitle reads "Resetting...".
- On success a message says "Tutorial will show on the main screen." Go back to the main screen and the card starts again at step 1.
- On failure a message says "Could not reset the tutorial. Try again." and the subtitle reads "Could not reset the tutorial. Tap to retry." Tap the row again to retry. The earlier state is kept until a reset succeeds.
- Pressing the row again while a reset is already running joins it instead of starting another.

## Setup completion is separate

Onboarding has its own saved flag. On the last onboarding screen **Start Bluey** saves setup first and only then moves on. If that save fails you see "Could not save setup. Tap Start Bluey to try again." and stay on the summary. That is not the tutorial. **Finish setup later** is also an onboarding action. Replaying the tutorial does not redo onboarding, and finishing onboarding does not finish the tutorial.

The tutorial flag and the onboarding flag are two separate saved values. Deleting local data in Settings clears both saved values along with everything else.

## Waking Bluey without the tutorial

You can wake Bluey any time with a double tap on his face, and the tutorial is not required for that. See the [user guide](USER_GUIDE.md) for gestures and voice. Skipping the tutorial does not change what Bluey can do.

## Limits

- The tests behind this page use fake or mock preference storage and fake owners. They do not show behavior on a real device or in real storage faults.
- Nothing here retries automatically or recovers on its own. Retry is always a tap.
- This page makes no claim about physical erasure of stored data.

## Source and tests

- Tutorial controller: [`lib/services/tutorial.dart`](../lib/services/tutorial.dart)
- Card: [`lib/ui/tutorial_card.dart`](../lib/ui/tutorial_card.dart)
- Settings replay row: `_TutorialReplayTile` in [`lib/ui/settings_screen.dart`](../lib/ui/settings_screen.dart)
- Onboarding completion: [`lib/ui/onboarding_screen.dart`](../lib/ui/onboarding_screen.dart)
- Evidence for the replay row and onboarding completion states: [`issue-464`](evidence/issue-464/README.md), [`issue-463`](evidence/issue-463/README.md)
