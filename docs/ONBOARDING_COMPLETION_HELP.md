# Onboarding completion help

This page explains the last onboarding screen, **Setup summary**, and what "setup saved" does and does not mean. It is based on the current source and existing tests. It claims no device, permission or network result beyond that.

## What the summary screen shows

You reach **Setup summary** after the last permission step, or earlier with **Finish setup later**. Nothing is marked finished until you press **Start Bluey** on this screen.

- One row per permission. A granted permission says "Available." A permission that is not granted says what stays off, for example "Bluey cannot click or type for you."
- A line says you can change any of these later in System Settings, and that Bluey tells you when a missing permission blocks something.
- A first-request area. While Bluey checks your chat model endpoint and speech-to-text configuration it says "Checking your chat model and speech setup...". Then it either shows a suggested first request to ask by holding the face, or "Not ready for a spoken question yet" with the specific issues and, where it applies, an **Open Settings** button.
- If pointing is not available, a note says the tutorial will skip pointing for now.

**Start Bluey** stays disabled and reads "Checking..." until that check has finished. **Back to setup** returns to the permission steps and is disabled while a save is running.

## Start Bluey

1. Press **Start Bluey**.
2. Bluey saves the setup-completed flag first.
3. Only after the save succeeds, and only if you are still on this screen, Bluey hands the first-request plan to the tutorial and then opens the main screen. This happens once.

Pressing **Start Bluey** again while a save is running does nothing extra; the presses share one attempt. If you leave the screen while the save is running, no late hand-off happens.

If the save fails, you stay on the summary and see "Could not save setup. Tap Start Bluey to try again." Nothing retries on its own. Press **Start Bluey** again to make a fresh attempt. The message is generic and shows no technical detail. **Back to setup** works again after the failure.

## What "setup saved" means

The saved flag only records that you pressed **Start Bluey** and the save worked. It is not:

- a permission grant. Permissions are checked live when the summary opens; a "Not enabled" permission stays off after you start.
- a test that speech-to-text works. When the summary opens, Bluey probes the chat model endpoint only. For speech-to-text it only reads the saved configuration: a non-empty HTTP base address, or the native kind, counts as ready. That does not check reachability, credentials, model, language or native capability, and it runs no recognition. The native option is a placeholder that is not qualified. These checks only shape the suggested first request.
- the tutorial. The tutorial has its own saved flag and its own skip and replay. See the [first-steps tutorial help](TUTORIAL_HELP.md).
- a promise about the network. The Local network permission has no check here. The screen text only says macOS may ask for it when your iPhone first looks for this Mac; that prompt was not verified.

Permissions you chose to set up later stay recorded as "later" and are kept apart from the step-reviewed progress, so moving through steps never counts as a grant.

## Notices (English and Hebrew)

| Where | English | Hebrew |
| --- | --- | --- |
| Save failed | Could not save setup. Tap Start Bluey to try again. | לא ניתן לשמור את ההגדרה. לחצו על התחל עם בלואי כדי לנסות שוב. |
| Start button | Start Bluey / Checking... | התחל עם בלואי / בודק... |
| Back | Back to setup | חזרה להגדרה |
| Finish early | Finish setup later | סיים את ההגדרה מאוחר יותר |

## Evidence and limits

- The five completion cases (shared presses, async false and thrown save failure with retry, disposal while saving, a real preferences save before the hand-off) are in [`test/onboarding_completion_test.dart`](../test/onboarding_completion_test.dart).
- Synthetic images of the pending, error, retry-pending and success states in English and Hebrew, at two widths and two text scales, are in [`docs/evidence/issue-463/`](evidence/issue-463/README.md). They are rendered by a test harness with fake storage and a fake permission checker. They are not device screenshots.
- This page does not claim real permission prompts, real storage faults, a reachable endpoint or any physical erase.

## Source

- Screen: [`lib/ui/onboarding_screen.dart`](../lib/ui/onboarding_screen.dart)
- First-request plan: [`lib/services/first_success.dart`](../lib/services/first_success.dart)
