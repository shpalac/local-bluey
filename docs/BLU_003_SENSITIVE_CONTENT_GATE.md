# BLU-003 — SensitiveContentGate: boundaries and evidence

**Status:** code review required. **Owner decision:** [#556](https://github.com/shpalac/local-bluey/issues/556). **Dependency:** BLU-001 privacy design [PR #665](https://github.com/shpalac/local-bluey/pull/665), not assumed merged.

## What the code now does

- `SensitiveContentGate.beforeCapture` checks front-app and window-title metadata **before** any watch frame-diff, event buffering, vision or screenshot work. Unknown/blank app or title, overlong metadata, locked/private windows, authentication and banking keywords, and patterns recognized by `PrivacyGuard.hasSensitive` are denied.
- `WatchPipeline.tick` checks the session and existing `WatchPolicy` allowlist first, then invokes this conservative metadata gate before `_process`. Denied windows produce no buffered content or pixel work; the existing excluded counter continues to count hard-denied/private/locked cases where WatchPolicy detects them.
- `WatchVision.describe` independently checks the app/title before capture. It accepts only a **verified** `ScreenSnapshot` whose OCR belongs to the exact image returned by the native crop bridge, whose front-app identity matches, and whose text passes PII/secret patterns.
- Before any model image egress, a fresh frontmost-app/title/lock read must match the original context. A changed or unreadable context refuses the frame. The existing per-session local-only and consent checks remain mandatory.
- A model reply that contains recognized secrets/PII is discarded before it reaches watch events. There is no new persistent data store, analytics, network endpoint, or logging of raw input. The only public result from the classifier is an enum reason.

## Native integration and limitations

**Production vision is OFF in this PR.** `lib/main.dart` no longer constructs `WatchVision` or passes a vision callback to `WatchPipeline`, so no vision capture, model call or vision event text happens. Watch ticks keep running (metadata-gated app events and frame diffs continue); a pipeline test proves ticks continue with no vision event and nothing sent. Reasons: the native `snapshotRegion` bridge reports the app from a cached earlier snapshot (`lastSnapshot`), not the focus at the moment of the crop, so crop identity and focus are not atomic with the pixels; and a full-display capture can contain background sensitive pixels outside the window that passed the metadata check. The only capture left is the existing frame-diff tick, which now runs only after the metadata gate allows it. `WatchVision`, `SensitiveContentGate.beforeEgress` and their fixtures are pure Dart and only prove the fail-closed logic; turning production vision on needs exact-crop classification and atomic focus evidence validated on a real macOS device (separate owner/device gate).

Empty or whitespace-only OCR text is denied: text-free pixels (an image, a drawing, a blank crop) cannot be classified by OCR, so they stay unknown and are never sent.

This is defense in depth, **not perfect classification or guaranteed data-loss prevention**:
- Vision OCR can miss text, Hebrew/English regexes have false positives and negatives, and a screen may show sensitive visual content without recognized text.
- Foreground windows may change between native capture, OCR and the final signal check. The fresh check reduces but does not eliminate this time-of-check/time-of-use race. Comprehensive prevention requires an atomic native window-capture policy and real-device tests.
- The native `snapshotRegion` path has only previously documented native/code evidence; macOS Screen Recording and Accessibility with real switching/private windows must be tested manually before claiming production hardening.
- The gate is in **proactive screen-watch and WatchVision only**. Conversational `look_at_screen` and `zoom_screen` still use existing `PrivacyGuard`/OCR checks, which have separate limitations. This PR must not be described as a universal screen capture policy.

## Denial and recovery

| Situation | Result |
| --- | --- |
| No session, revocation or expired consent | No work starts; in-flight result discarded |
| Unknown/empty/oversized app or title | No frame-diff, watch event or vision |
| Private/password/banking/login title | No frame-diff, watch event or vision |
| OCR failed, absent or oversized | No image goes to the model |
| English/Hebrew sensitive patterns or credentials | No image egress; reason code only |
| Focus changes during OCR | No image egress |
| Provider returns known-sensitive summary | No watch event produced |
| User explicitly starts a new safe session | Ordinary flow resumes after policy recheck |

## Validation

- `flutter test test/sensitive_content_gate_test.dart`
- `flutter test test/watch_vision_test.dart test/watch_pipeline_test.dart test/watch_driver_test.dart test/watch_driver_lifecycle_test.dart`
- `flutter analyze`
- `dart format --set-exit-if-changed lib test`
- CI's emulator/macOS build lanes as applicable. Native TCC and physical devices **not** verified by mock tests.

**Rollback:** revert this isolated commit series if the new metadata contract breaks native capture. Rollback loosens observation defenses, so the safer mitigation for an unverified release is disabling optional screen watching rather than reverting the gate. This is intentionally fail-closed even if some legitimate windows cannot be classified.
