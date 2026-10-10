import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/haptics.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Settings haptics clear, failed toggle and recovery stay honest',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'brain.baseUrl': 'http://localhost:1234/v1',
        'brain.model': 'fixture',
      });
      bool? stored = false;
      var failWrite = false;
      final service = RemoteHaptics.forTest(
        read: () async => stored,
        write: (value) async {
          if (failWrite) return false;
          stored = value;
          return true;
        },
        remove: () async {
          stored = null;
          return true;
        },
      );
      RemoteHaptics.debugOverride = service;
      addTearDown(() {
        RemoteHaptics.debugOverride = null;
        service.dispose();
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        ),
      );
      tester.view.physicalSize = const Size(1000, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();
      Finder toggle() => find.descendant(
        of: find.widgetWithText(SwitchListTile, 'Haptics'),
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(toggle()).value, isFalse);
      final tile = find.widgetWithText(ListTile, 'Haptics on/off preference');
      await tester.tap(
        find.descendant(of: tile, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      expect(stored, isNull);
      expect(service.enabled, isTrue);
      expect(tester.widget<Switch>(toggle()).value, isTrue);
      failWrite = true;
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(stored, isNull);
      expect(tester.widget<Switch>(toggle()).value, isTrue);
      expect(
        find.text('Could not update haptics. Please retry.'),
        findsOneWidget,
      );
      failWrite = false;
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(stored, isFalse);
      expect(tester.widget<Switch>(toggle()).value, isFalse);
      expect(
        find.text('Could not update haptics. Please retry.'),
        findsNothing,
      );
    },
  );
}
