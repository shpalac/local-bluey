# TutorialCard completion evidence

Refs #466. Source baseline: main `9bb59d99d53282af6bbe46a047bed0078732a97e`.

## What changed

The actual TutorialCard awaits the existing owner's skip completion, disables repeated activation while that caller is pending, shows the current owner's safe storage failure and offers explicit retry through skip. Owner replacement fences late completion; a disposed caller cannot set state. No automatic retry or reset was added. TutorialController, Settings, startup, onboarding and watchdog are unchanged.

The title can wrap and the progress/action row can wrap at compact width and 2x text. Only the new notice, retry and saving labels use EN/HE strings. Existing title, instructions and skip text remain unchanged, including English instructions in the RTL fixture.

## Behavioral proof

`test/tutorial_card_completion_test.dart` uses the actual TutorialCard and TutorialController with an injected TutorialDoneStore. It checks:

- A held successful skip keeps the card visible, blocks repeated activation and writes once before success hides it.
- Thrown persistence failures are contained, display only the safe generic notice and do not retry automatically. Explicit held retry writes once more and hides only after success.
- An actual SharedPreferences false platform return reaches the owner's failure handling and visible recovery, then succeeds on explicit retry.
- Natural answer and optional point completion failures remain visible and recover through explicit skip retry.
- Removal during held success or failure, owner replacement and reentrant removal do not cause late UI updates or reset writes.

The pixel fixtures also assert no framework exception, a control of at least 48x48 logical pixels and an actual tap on Retry. The pending screenshot starts a fresh fixture attempt after an explicit test-only reset. That reset is not a production retry or UI behavior.

## Validation

Fresh locked dependencies, Dart formatting and Flutter analysis passed. The new test file has 17 passing cases (9 behavior and 8 visual configurations). It and the unchanged tutorial, tutorial replay, tutorial gating and first-success files passed together: 47 tests.

Commands:

```sh
flutter pub get --enforce-lockfile
 dart format --output=none --set-exit-if-changed lib/ui/tutorial_card.dart test/tutorial_card_completion_test.dart
flutter analyze
flutter test test/tutorial_card_completion_test.dart test/tutorial_test.dart test/tutorial_replay_test.dart test/tutorial_gating_test.dart test/first_success_test.dart
TUTORIAL_PIXELS=1 FLUTTER_ROOT=/tmp/flutter-local flutter test test/tutorial_card_completion_test.dart
```

Pixel generation loads the repo Roboto font, local Noto Sans Hebrew and Flutter MaterialIcons only when TUTORIAL_PIXELS=1. Normal CI does not need those local font paths or generate evidence. Dependency files were not changed. An initial compact 2x title overflow was fixed before these captures and passing runs.

## Actual pixels

All 24 originals were inspected at their recorded size. The notice and controls are readable without clipping or overflow in each configuration. These are synthetic widget-rendered fixtures at 320/1000 logical pixels wide, 900 high, DPR 1, with 1x/2x text. They are not mounted-home screenshots or native OS durability/first-answer evidence.

Error shows a settled rejected write and enabled explicit retry. Retry shows that explicit retry still held, with the previous safe notice retained and Saving disabled. Pending shows a held first attempt with no error notice.

| Width | Text | Language | Error | Retry held | First attempt held |
| --- | --- | --- | --- | --- | --- |
| 320 | 1x | EN | [Error](320-1-en-error.png) | [Retry held](320-1-en-retry.png) | [Pending](320-1-en-pending.png) |
| 320 | 1x | HE | [Error](320-1-he-error.png) | [Retry held](320-1-he-retry.png) | [Pending](320-1-he-pending.png) |
| 320 | 2x | EN | [Error](320-2-en-error.png) | [Retry held](320-2-en-retry.png) | [Pending](320-2-en-pending.png) |
| 320 | 2x | HE | [Error](320-2-he-error.png) | [Retry held](320-2-he-retry.png) | [Pending](320-2-he-pending.png) |
| 1000 | 1x | EN | [Error](1000-1-en-error.png) | [Retry held](1000-1-en-retry.png) | [Pending](1000-1-en-pending.png) |
| 1000 | 1x | HE | [Error](1000-1-he-error.png) | [Retry held](1000-1-he-retry.png) | [Pending](1000-1-he-pending.png) |
| 1000 | 2x | EN | [Error](1000-2-en-error.png) | [Retry held](1000-2-en-retry.png) | [Pending](1000-2-en-pending.png) |
| 1000 | 2x | HE | [Error](1000-2-he-error.png) | [Retry held](1000-2-he-retry.png) | [Pending](1000-2-he-pending.png) |
