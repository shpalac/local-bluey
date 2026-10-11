# App lock help

This page describes what the optional app lock does today, in the words the app uses. It is based on the current source and the existing tests. It does not promise more than that.

App lock is off by default. Nothing is locked until you turn it on.

## What it locks

When app lock is on, two things sit behind device authentication:

- the phone remote screen (the phone client home; the source maps both iOS and Android to the phone client), and
- Bluey Settings, opened from the Mac onboarding screen or from the settings icon on the Mac home screen.

Other screens, network traffic and stored data are not locked or encrypted by this switch. It is a screen gate, not a security guarantee beyond those gated screens.

## Turn it on

1. Open Settings (it asks you to unlock first if the lock is already on).
2. Find the **App lock** row. Its subtitle reads "Require device biometrics or passcode for the remote and Settings."
3. Switch it on. The system asks you to authenticate. The system accepts biometrics or the device passcode.
4. The lock turns on only after authentication succeeds and the choice is saved. If either step fails the switch stays off.

If it stays off, the subtitle says why:

| Message under the switch | What it means | What to do |
| --- | --- | --- |
| "App lock was not enabled. Set up a device passcode or biometrics in system settings and try again." | The device has no passcode or biometrics set up, or authentication is not available. | Set one up in the system settings, then switch it on again. |
| "App lock was not enabled because authentication was not completed." | You cancelled or did not pass the prompt. | Switch it on again and complete the prompt. |
| "Could not save app lock. Try again and check device authentication in system settings." | Authentication may have worked, but it could not start or the choice could not be saved. | Try again. If it repeats, check device authentication in system settings. |

## Unlock

A locked screen shows "Bluey is locked." and an **Unlock** button. Unlocking asks for biometrics or the device passcode.

- Bluey asks for authentication when a gated screen opens, and when you press Unlock. It does not start a new prompt by itself when you return from the background.
- Sending Bluey to the background locks the screen again. Returning to it shows the locked screen, and you press **Unlock**.
- The system prompt itself can briefly make the app inactive. That does not cancel the attempt in progress.
- A result that arrives after you backgrounded the app, or after the screen was closed, is ignored. It cannot unlock anything.

If unlocking does not work, the locked screen says:

| Message | What to do |
| --- | --- |
| "Authentication was not completed. Bluey is still locked." | Press **Unlock** and complete the prompt. |
| "Device authentication is not set up. Set a device passcode or biometrics in system settings, then retry." | Set one up in the system settings, then press **Unlock**. |
| "Authentication could not start. Try again. If the problem continues, check device authentication in system settings." | Press **Unlock** again, then check device authentication in system settings. |

There is no bypass. A failed or missing authentication always keeps the gate locked.

## Turn it off

Inside unlocked Settings, switch **App lock** off. Turning it off does not ask for another prompt, because you are already past the gate. Failed authentication never turns an enabled lock off.

## Clear the preference

Settings has a **Data and privacy** section. The row "App-lock on/off preference" has a **Clear** button, and **Delete all local data** clears it with everything else.

- A successful clear removes the saved preference and the switch shows off right away, without restarting the app.
- If you were in the middle of enabling the lock and the clear happens first, the old authentication result is discarded and does not turn the lock back on. Enabling again needs a fresh authentication.
- If the preference cannot be removed, you see "Could not delete local data: Could not remove the app-lock preference". The lock keeps its current state. Press **Clear** again to retry.

## Limits

- The tests behind this page use fake authenticators and mock or injected preference storage. They do not exercise real Touch ID, Face ID, a device passcode or a physical device. Those remain unverified.
- Clearing the preference removes the saved on/off value in the app's preference store. This page makes no claim about physical erasure of storage.
- This page does not describe the operating system's own prompt behavior, such as how long a prompt stays valid.
- The existing README and user guide mention Touch ID and Face ID. In the current code the lock accepts biometrics with the device passcode as fallback.

## Source and tests

- Service and authenticator: [`lib/services/biometric_lock.dart`](../lib/services/biometric_lock.dart)
- Settings row: [`lib/ui/app_lock_tile.dart`](../lib/ui/app_lock_tile.dart)
- Gate: [`lib/ui/lock_gate.dart`](../lib/ui/lock_gate.dart)
- Clear route: the `app_lock_pref` entry in [`lib/services/data_registry.dart`](../lib/services/data_registry.dart)
- Tests: [`test/biometric_lock_test.dart`](../test/biometric_lock_test.dart), [`test/lock_gate_test.dart`](../test/lock_gate_test.dart)
- Images: [`issue-363-applock-clear-failed-en.png`](evidence/issue-363-applock-clear-failed-en.png), [`issue-363-applock-clear-recovered-he.png`](evidence/issue-363-applock-clear-recovered-he.png)
