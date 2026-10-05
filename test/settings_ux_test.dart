import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/safety_gate.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('time-boxed gate pause (#133)', () {
    test('pauseFor disables until the deadline, then re-enables', () async {
      final gate = SafetyGate();
      expect(await gate.isEnabled(), isTrue);
      await gate.pauseFor(const Duration(milliseconds: 40));
      expect(await gate.isEnabled(), isFalse);
      expect(await gate.resumeAt(), isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(await gate.isEnabled(), isTrue);
      expect(await gate.resumeAt(), isNull);
    });

    test('indefinite off stays off without a deadline', () async {
      final gate = SafetyGate();
      await gate.setEnabled(false);
      expect(await gate.isEnabled(), isFalse);
      await gate.setEnabled(true);
      expect(await gate.isEnabled(), isTrue);
    });
  });

  group('settings screen gate warning (#133)', () {
    testWidgets('turning the switch off asks first', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      // The screen loads via real platform-channel futures: give them a
      // real async window, then rebuild.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Safety gate'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final gateSwitch = find.widgetWithText(SwitchListTile, 'Safety gate');
      expect(gateSwitch, findsOneWidget);
      await tester.tap(
        find.descendant(of: gateSwitch, matching: find.byType(Switch)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The warning dialog appears instead of a silent toggle.
      expect(find.text('Turn off action confirmations?'), findsOneWidget);
      await tester.tap(find.text('Keep on'));
      await tester.pump();
      expect(await SafetyGate().isEnabled(), isTrue);
    });

    testWidgets('choosing Pause 15 min disables with a deadline and banner', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      // The screen loads via real platform-channel futures: give them a
      // real async window, then rebuild.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Safety gate'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'Safety gate'),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Pause 15 min'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(
        find.textContaining('PAUSED', skipOffstage: false),
        findsOneWidget,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('safety.enabled'), isNull); // saved only on Save
    });
  });
}
