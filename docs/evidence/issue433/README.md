# Explicit Accessibility settings action evidence

Base main4564b5293d247fdf2b8f26337288a7c43c0b80de, 11 October 2026. Notice-only action state; actual read-only TrustObservation and main askPermission then openAccessibilitySettings callback unchanged. No permission proof from action success. One explicit denied tap installs pending before queued entry; repeats suppressed and internal completion joined. Generic localized failure is retained privately across non-denied statuses and shown only if denial returns. No automatic retry or prompt. Queued status change/disposal prevents entry, entered work may finish without disposed UI update.

## Tests

`flutter test test/trust_settings_action_test.dart` (9 direct) and `flutter test test/trust_observation_notice_test.dart` (32 composed).

Actual notice tests: held/double/reentrant action, synchronous/asynchronous failures, explicit retry/success without grant inference, caller loading/granted/error/denied transitions, queued status cancellation, callback after teardown, queued and entered disposal. Controlled real MacHostControl/NativeControl MethodChannel callback verifies isTrusted-only read and askPermission then settings order, including failure short circuit. It is mocked channel evidence, not real OS permission/native/device proof. Main callback source assertion remains in trust_observation_test.dart.

Initial direct+composed40 passed. Added queued-disposal attempt failed because pumpWidget flushed callback microtask before replacement, so it tested entered disposal instead. Repaired deterministic dispatch during replacement build, with disposal at finalization before microtasks; zero callback entry assertion passed, no weakened assertion, sleep or new skip. Final direct9 passed, composed32 passed with pixels. Full135-file suite split in disjoint sorted batches:424 +476/skip1 +646 +341 =1887 pass/skip1. Existing skip unchanged. Analyze clean; dart format lib/test238 files zero changes; diff check clean. Initial pre-pub format warned unresolved flutter_lints; pub get resolved it before checks. Generated plugin/local.properties noise restored; benchmark Python cache removed. Current PR CI remains separate from these local runs.

## Pixels

Generate with `TRUST_PIXELS=1 FLUTTER_ROOT=/tmp/flutter-local flutter test test/trust_observation_notice_test.dart`. 32 actual-widget compositions: normal/onboarding,320/1000 width,1x/2x, EN/Hebrew RTL, light/dark. Capture pending/error content and disabled/retry actions at successive scroll positions. Existing host/hold/key notices, independent FaceScreen request bubble or actual onboarding body and normal recovery/settings/close controls remain. No overflows/exceptions; other notice actions/body controls tapped without new recording/wake effects. Existing compact2x onboarding heading/chips truncate as before, not repaired here.

16 contact sheets contain128 action images. Three full decisive originals attached below. Shared region may require successive scrolling to read complete text and reach actions; button-focused captures can omit notice top, top-focused captures can omit lower controls. No single screenshot claims simultaneous visibility. Inspected all sheets and full originals for readable text, RTL wrapping, disabled/retry actions and independent content.

- [Compact EN2x normal error](433-320-2-en-light-normal-action-error-top.png)
- [Compact RTL2x onboarding pending](433-320-2-he-dark-onboard-action-pending-button.png)
- [Regular RTL2x normal error action](433-1000-2-he-light-normal-action-error-button.png)

- [Sheet 00](433-sheet-00.png)
- [Sheet 01](433-sheet-01.png)
- [Sheet 02](433-sheet-02.png)
- [Sheet 03](433-sheet-03.png)
- [Sheet 04](433-sheet-04.png)
- [Sheet 05](433-sheet-05.png)
- [Sheet 06](433-sheet-06.png)
- [Sheet 07](433-sheet-07.png)
- [Sheet 08](433-sheet-08.png)
- [Sheet 09](433-sheet-09.png)
- [Sheet 10](433-sheet-10.png)
- [Sheet 11](433-sheet-11.png)
- [Sheet 12](433-sheet-12.png)
- [Sheet 13](433-sheet-13.png)
- [Sheet 14](433-sheet-14.png)
- [Sheet 15](433-sheet-15.png)
