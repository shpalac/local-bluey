# Fabricated disabled Routine review card

Four actual Flutter pixels inspected:320x844, EN and Hebrew RTL,1x/2x text. Text wraps and Accept/Decline remain readable in these short fabricated fixtures. No deployed UI/store/provider data. At large content a caller must provide scrolling, as fixture does.

Reproduce on Linux with Flutter, DejaVuSans installed:
`mkdir -p /tmp/review564-pixels`
`REVIEW_PIXELS=/tmp/review564-pixels flutter test test/routine_review_card_test.dart --reporter expanded`

Six new widget fixtures/32 focused passes with existing routines tests. Tap pending/no duplicate, safe failure/retry/decline, enabled Routine refused, keyboard Enter and semantic button action. Semantic tree is not native VoiceOver proof. This standalone component is not wired to screen watching or routine storage. Does not edit structured steps, create/persist a draft, retain decline/never state or run anything. Displayed fields must be separately validated and privacy-authorized by future caller.

Rollback new widget/test/evidence/map. Existing watcher/routines unchanged.
