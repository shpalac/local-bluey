import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/ui/routine_review_card.dart';

void main() {
  const draft = Routine(name: 'Morning', trigger: 'morning',
    instructions: 'Open calendar', enabled: false);

  Future<void> mount(WidgetTester tester, Future<void> Function(Routine) accept) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: RoutineReviewCard(
        routine: draft, onAccept: accept, onDecline: () {},
      )),
    )));
    await tester.ensureVisible(find.text('Edit draft'));
    await tester.tap(find.text('Edit draft'));
    await tester.pump();
  }

  testWidgets('AC-1 original and edited instructions visible before accepting', (tester) async {
    await mount(tester, (_) async {});
    await tester.enterText(find.byKey(const ValueKey('workflow-draft-instructions')), 'Show agenda');
    await tester.pump();
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    expect(find.text('Open calendar'), findsWidgets);
    expect(find.text('Show agenda'), findsWidgets);
  });

  testWidgets('AC-2 invalid instructions disable acceptance with explicit error', (tester) async {
    var accepts = 0;
    await mount(tester, (_) async { accepts++; });
    await tester.enterText(find.byKey(const ValueKey('workflow-draft-instructions')), '   ');
    await tester.pump();
    expect(find.text('Invalid draft fields'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(accepts, 0);
  });

  testWidgets('valid edited instructions are handed off as a disabled draft', (tester) async {
    Routine? accepted;
    await mount(tester, (value) async { accepted = value; });
    await tester.enterText(find.byKey(const ValueKey('workflow-draft-instructions')), 'Show agenda');
    await tester.pump();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(accepted?.instructions, 'Show agenda');
    expect(accepted?.enabled, isFalse);
  });
}
