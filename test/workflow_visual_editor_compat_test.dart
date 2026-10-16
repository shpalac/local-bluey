import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/ui/routine_review_card.dart';

void main() {
  const draft = Routine(
    name: 'Morning',
    trigger: 'morning',
    instructions: 'Open calendar',
    enabled: false,
  );

  final accepted = <Routine>[];
  Future<void> collect(Routine proposal) async {
    accepted.add(proposal);
  }

  setUp(accepted.clear);

  const flavors = [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ];

  Future<void> mount(WidgetTester tester, {required Routine routine}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoutineReviewCard(
              key: UniqueKey(),
              routine: routine,
              onAccept: collect,
              onDecline: () {},
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byType(FilledButton));
  }

  testWidgets('ac4 editor behavior is identical across flavors', (
    tester,
  ) async {
    final before = draft.toJson();

    for (final platform in flavors) {
      debugDefaultTargetPlatformOverride = platform;
      await mount(tester, routine: draft);

      await tester.ensureVisible(find.text('Edit draft'));
      await tester.tap(find.text('Edit draft'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('workflow-draft-instructions')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('workflow-draft-instructions')),
        'Show agenda',
      );
      await tester.pump();
      expect(find.text('Before'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
      expect(find.text('Open calendar'), findsWidgets);
      expect(find.text('Show agenda'), findsWidgets);

      await tester.ensureVisible(find.byType(FilledButton));
      final beforeCount = accepted.length;
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(accepted, hasLength(beforeCount + 1));
      expect(accepted.last.enabled, isFalse, reason: 'review stays disabled');
      expect(accepted.last.instructions, 'Show agenda');
      debugDefaultTargetPlatformOverride = null;
    }
    expect(accepted, hasLength(3));

    // The legacy draft itself remains byte-identical throughout.
    expect(draft.toJson(), before);
  });

  testWidgets('ac4 live routines stay outside the editor', (tester) async {
    const enabled = Routine(
      name: 'Live',
      trigger: 'go',
      instructions: 'Old',
      enabled: true,
    );
    final before = enabled.toJson();

    for (final platform in flavors) {
      debugDefaultTargetPlatformOverride = platform;
      await mount(tester, routine: enabled);
      expect(
        find.byKey(const ValueKey('workflow-draft-instructions')),
        findsNothing,
      );
      expect(
        find.text('Only a disabled draft can be reviewed here.'),
        findsOneWidget,
      );
      // The acceptance affordance stays inactive for a live routine;
      // only decline remains reachable.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      debugDefaultTargetPlatformOverride = null;
    }
    expect(accepted, isEmpty);
    expect(enabled.toJson(), before);
  });
}
