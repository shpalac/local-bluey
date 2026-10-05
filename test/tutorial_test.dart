import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local_bluey/services/tutorial.dart';
import 'package:local_bluey/ui/tutorial_card.dart';

TutorialController _controller(SharedPreferences prefs) =>
    TutorialController(prefsOverride: prefs);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TutorialController', () {
    test('starts at wake and walks wake -> ask -> point -> done', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _controller(prefs);
      expect(c.step, TutorialStep.wake);
      expect(c.visible, isTrue);
      expect(await TutorialController.isDone(prefs), isFalse);

      c.notifyAnswer(); // out of order: ignored
      expect(c.step, TutorialStep.wake);

      c.notifyAwake();
      expect(c.step, TutorialStep.ask);
      c.notifyAwake(); // repeat: ignored
      expect(c.step, TutorialStep.ask);

      c.notifyAnswer();
      expect(c.step, TutorialStep.point);
      c.notifyPointed();
      await Future<void>.delayed(Duration.zero);
      expect(c.visible, isFalse);
      expect(await TutorialController.isDone(prefs), isTrue);
    });

    test('skip finishes at any step and persists', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _controller(prefs);
      await c.skip();
      expect(c.visible, isFalse);
      expect(await TutorialController.isDone(prefs), isTrue);
      // Events after skip do nothing.
      c.notifyAwake();
      expect(c.visible, isFalse);
    });

    test('reset clears the flag and starts over (replay)', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _controller(prefs);
      await c.skip();
      await c.reset();
      expect(c.visible, isTrue);
      expect(c.step, TutorialStep.wake);
      expect(await TutorialController.isDone(prefs), isFalse);
    });

    test('dismiss hides without persisting; reset brings it back', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _controller(prefs);
      c.dismiss();
      expect(c.visible, isFalse);
      expect(await TutorialController.isDone(prefs), isFalse);
      await c.reset();
      expect(c.visible, isTrue);
    });
  });

  group('TutorialCard', () {
    testWidgets('shows the current instruction, progress and skip', (t) async {
      final prefs = await SharedPreferences.getInstance();
      final c = _controller(prefs);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TutorialCard(controller: c)),
        ),
      );
      expect(find.text('First steps'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.textContaining('Double-tap'), findsOneWidget);
      expect(find.text('Skip tutorial'), findsOneWidget);

      c.notifyAwake();
      await t.pump();
      expect(find.text('2/3'), findsOneWidget);
      expect(find.textContaining('Press and hold'), findsOneWidget);

      await t.tap(find.text('Skip tutorial'));
      await t.pump();
      expect(find.text('First steps'), findsNothing);
    });
  });
}
