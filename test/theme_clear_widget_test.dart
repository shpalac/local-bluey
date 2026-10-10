import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/ui/theme.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'actual Settings theme clear refreshes System and fresh choices',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'theme.mode': 'dark',
        'brain.baseUrl': 'http://localhost:1234/v1',
        'brain.model': 'fixture',
      });
      final temp = await tester.runAsync(
        () => Directory.systemTemp.createTemp('theme-widget'),
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => temp!.path,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );
      addTearDown(() async {
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
        await tester.runAsync(() => temp!.delete(recursive: true));
      });
      await tester.runAsync(() => ThemeController.instance.load());
      tester.view.physicalSize = const Size(1000, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();
      Finder dropdown() => find.descendant(
        of: find.widgetWithText(ListTile, 'Appearance'),
        matching: find.byType(DropdownButton<ThemeMode>),
      );
      expect(
        tester.widget<DropdownButton<ThemeMode>>(dropdown()).value,
        ThemeMode.dark,
      );
      final tile = find.widgetWithText(
        ListTile,
        'Appearance override (system/light/dark)',
      );
      await tester.runAsync(() async {
        tester
            .widget<IconButton>(
              find.descendant(of: tile, matching: find.byType(IconButton)),
            )
            .onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getString('theme.mode'),
        isNull,
      );
      expect(
        tester.widget<DropdownButton<ThemeMode>>(dropdown()).value,
        ThemeMode.system,
      );
      await tester.runAsync(
        () => ThemeController.instance.setMode(ThemeMode.light),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButton<ThemeMode>>(dropdown()).value,
        ThemeMode.light,
      );
    },
  );
}
