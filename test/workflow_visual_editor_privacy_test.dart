import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/routine_proposal.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/ui/routine_review_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const draft = Routine(
    name: 'Morning',
    trigger: 'morning',
    instructions: 'Open calendar',
    enabled: false,
  );

  int accepted = 0;
  List<Routine> handed = [];
  Future<void> collect(Routine proposal) async {
    accepted++;
    handed.add(proposal);
  }

  setUp(() {
    accepted = 0;
    handed = [];
  });

  Future<void> mount(WidgetTester tester, {Routine? routine}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoutineReviewCard(
              routine: routine ?? draft,
              onAccept: collect,
              onDecline: () {},
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Edit draft'));
    await tester.tap(find.text('Edit draft'));
    await tester.pump();
  }

  test('ac3 editor surface keeps a no-io, no-network, no-writer contract', () {
    final source = File('lib/ui/routine_review_card.dart').readAsStringSync();
    expect(
      source.contains(RegExp("import '(dart:io|dart:convert|package:http)")),
      isFalse,
      reason: 'the editor must not gain transport or filesystem access',
    );
    expect(
      source.contains(
        RegExp('HttpClient|SharedPreferencesWithCache|writeAsBytes'),
      ),
      isFalse,
      reason: 'the editor must not gain network or artifact writers',
    );
  });

  testWidgets('ac3 edits stay disabled-only and never persist', (tester) async {
    final prefs = <String, Object>{};
    SharedPreferences.setMockInitialValues(prefs);
    await mount(tester);
    for (final secret in [
      'hunter2',
      'sample@fixture.invalid',
      '4111-1111-1111-1111',
    ]) {
      await tester.enterText(
        find.byKey(const ValueKey('workflow-draft-instructions')),
        'notify now with $secret',
      );
      await tester.pump();
      expect(find.text('Invalid draft fields'), findsNothing);
      expect(handed, isEmpty, reason: 'nothing is handed off without a tap');
    }

    // Acceptance stays available only while the proposal keeps the draft
    // disabled; the call never activates anything.
    await tester.enterText(
      find.byKey(const ValueKey('workflow-draft-instructions')),
      'notify now with hunter2',
    );
    await tester.pump();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(accepted, 1);
    expect(handed.single.enabled, isFalse);
    expect(handed.single.instructions, 'notify now with hunter2');

    // And nothing reached storage through the editor flow.
    expect(prefs, isEmpty);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('ac3 off-contract edits fail closed without echo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await mount(tester);
    final oversized = List.filled(
      RoutineStore.maxInstructionsChars + 1,
      'a',
    ).join();
    final attempted = ['   ', oversized];

    for (final text in attempted) {
      await tester.enterText(
        find.byKey(const ValueKey('workflow-draft-instructions')),
        text,
      );
      await tester.pump();
      // The explicit invalid notice is shown and the clip stays disabled
      // for every off-contract shape; nothing is stored or executed.
      expect(find.text('Invalid draft fields'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(handed, isEmpty);
      // The typed exception never embeds the attempted input.
      try {
        RoutineProposal.fromFields({
          'name': draft.name,
          'trigger': draft.trigger,
          'instructions': text,
        });
        fail('RoutineProposal must refuse off-contract fields');
      } on RoutineProposalException catch (e) {
        expect(e.toString(), 'Routine proposal fields are invalid.');
        expect(e.toString(), isNot(contains(text)));
      }
    }
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
}
