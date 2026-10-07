import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> secrets;
  late Directory temp;
  var failDelete = false;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('settings-deletion');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => temp.path,
        );
    secrets = {'brain.apiKey': 'old-secret'};
    failDelete = false;
    SharedPreferences.setMockInitialValues({
      'brain.backend': 'openAiCompatible',
      'brain.baseUrl': 'http://old.local/v1',
      'brain.model': 'old-model',
      'onboarding.done': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final key = call.arguments?['key'] as String?;
          switch (call.method) {
            case 'read':
              return secrets[key];
            case 'delete':
              if (failDelete) throw PlatformException(code: 'locked');
              secrets.remove(key);
            case 'write':
              secrets[key!] = call.arguments['value'] as String;
            case 'deleteAll':
              secrets.clear();
          }
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await temp.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester, {VoidCallback? onDeleteAll}) async {
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(onDeleteAll: onDeleteAll),
                ),
              ),
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
  }

  Future<void> clearSettings(WidgetTester tester) async {
    final tile = find.widgetWithText(
      ListTile,
      'Brain/provider settings and the API key (Keychain)',
    );
    final button = find.descendant(of: tile, matching: find.byType(IconButton));
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('clear then save cannot restore old key or endpoint (#247)', (
    tester,
  ) async {
    await open(tester);
    await clearSettings(tester);
    expect(secrets['brain.apiKey'], isNull);
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(
      fields.any((field) => field.controller?.text == 'old-secret'),
      isFalse,
    );
    expect(
      fields.any((field) => field.controller?.text == 'http://old.local/v1'),
      isFalse,
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.widgetWithText(FilledButton, 'Save').hitTestable());
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('brain.baseUrl'), isNot('http://old.local/v1'));
    expect(secrets['brain.apiKey'], isNull);
  });

  testWidgets(
    'deliberately entered settings save normally after clear (#247)',
    (tester) async {
      await open(tester);
      await clearSettings(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Base URL'),
        'http://new.local/v1',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.widgetWithText(FilledButton, 'Save').hitTestable());
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getString('brain.baseUrl'),
        'http://new.local/v1',
      );
      expect(secrets['brain.apiKey'], isNull);
    },
  );

  testWidgets('delete-all closes the form and requests first-run (#247)', (
    tester,
  ) async {
    var firstRun = false;
    final stores = DataRegistry.stores.toList();
    DataRegistry.stores.clear();
    addTearDown(() => DataRegistry.stores.addAll(stores));
    await open(tester, onDeleteAll: () => firstRun = true);
    await tester.tap(find.text('Delete all local data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete everything'));
    await tester.pumpAndSettle();
    expect(firstRun, isTrue);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(secrets, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getBool('onboarding.done'),
      isNull,
    );
  });

  testWidgets(
    'failed key deletion preserves editable state and reports error (#247)',
    (tester) async {
      await open(tester);
      await tester.pumpAndSettle();
      final keyController = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .firstWhere((field) => field.controller?.text == 'old-secret')
          .controller!;
      failDelete = true;
      await clearSettings(tester);
      expect(
        find.textContaining('Could not delete local data'),
        findsOneWidget,
      );
      expect(find.text('settings cleared'), findsNothing);
      expect(keyController.text, 'old-secret');
    },
  );
}
