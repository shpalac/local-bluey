# Data and privacy help

This page explains **Settings > Data and privacy**: the per-category **Clear** buttons and **Delete all local data**. It is based on the current source (`DataPrivacySection`, `DataRegistry`, `SettingsScreen`) and existing tests. It claims no device, secure-erase or native result beyond that.

## What the section lists

The section lists every category the app keeps on this device, from one inventory. Each row shows what is stored, where it lives and how long it is kept. Most rows say "Kept until you delete it". The action log keeps up to 500 entries / 30 days, and the egress record up to 300 entries / 30 days.

Categories that have their own help or limits:

- App-lock preference: see [App lock help](APP_LOCK_HELP.md).
- Egress record: see [Egress record and self-test limits](USER_GUIDE.md#egress-record-and-self-test-limits). It holds metadata from selected callers, not every connection, so it is not a full traffic record.
- First-steps tutorial flag: see [Tutorial help](TUTORIAL_HELP.md).

## Clear one category

1. Open Settings and scroll to **Data and privacy**.
2. Press the delete icon (tooltip **Clear**) on a row.

There is no confirmation for a single category. On success a notice says the category id followed by "cleared", for example "action_log cleared". If the clear fails, a notice says "Could not delete local data:" followed by the error. Press **Clear** again to retry; nothing retries on its own.

While any clear or delete-all is running, or while Settings is saving, all the **Clear** buttons and **Delete all local data** are disabled.

## Delete all local data

1. Press **Delete all local data**.
2. A dialog titled "Delete all local data?" says it wipes every store listed, the API key and pairing keys, and returns the app to first-run state, and that your remote provider account data is not touched.
3. Press **Delete everything** to continue, or **Cancel** to leave everything as it is.

On success a notice says "All local data deleted", the Settings screen closes and onboarding starts again.

### If it fails part way

Delete all works in two stages:

1. It tries every category in the inventory, in order. A category that fails does not stop the later ones; each is still attempted, and the failed ones are collected.
2. Only if every category cleared, it then clears the remaining saved preferences and the secure-storage items. If any category failed, this second stage is skipped.

If any category failed, you see a notice starting "Could not delete local data:" followed by the app's error text. It names the failed category ids, but its exact wording is not fixed, so this page does not quote it.

So a partial failure is not an all-or-nothing rollback. Every category that succeeded, whether it came before or after a failed one, stays cleared. The failed categories keep their data, and the remaining preferences and secure-storage items are not cleared. Press **Delete all local data** again to retry. Nothing retries on its own.

## Limits

- Remote provider account data is not touched. Only data on this device is covered.
- Downloaded speech model files that are still in use are removed when they are released, not at the moment you press the button. They can remain until then.
- The egress record is bounded metadata from selected callers. Clearing it does not say anything about what was sent earlier or later.
- This page does not describe a retention or erasure policy beyond the table the section itself shows. It does not claim secure or physical erase, and it does not claim any device or native-storage behavior.

## Source and tests

- Section: [`lib/ui/data_privacy_section.dart`](../lib/ui/data_privacy_section.dart)
- Inventory and delete all: [`lib/services/data_registry.dart`](../lib/services/data_registry.dart)
- Settings reaction to a clear: [`lib/ui/settings_screen.dart`](../lib/ui/settings_screen.dart)
- Tests: [`test/data_registry_test.dart`](../test/data_registry_test.dart), [`test/settings_deletion_test.dart`](../test/settings_deletion_test.dart), [`test/privacy_clear_widget_test.dart`](../test/privacy_clear_widget_test.dart), [`test/egress_registry_clear_test.dart`](../test/egress_registry_clear_test.dart), [`test/model_store_test.dart`](../test/model_store_test.dart)
