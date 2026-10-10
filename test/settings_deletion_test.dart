import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:local_bluey/services/perf_monitor.dart';
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
    SharedPreferences.setMockInitialValues({});
    await PerfMonitor.instance.clear();
    SettingsScreen.debugReadField = null;
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
    SettingsScreen.debugReadField = null;
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
  Future<void> clearStore(WidgetTester tester, String title) async {
    final tile = find.widgetWithText(ListTile, title);
    await tester.runAsync(() async {
      tester
          .widget<IconButton>(
            find.descendant(of: tile, matching: find.byType(IconButton)),
          )
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
  }

  Finder switchFor(String title) => find.descendant(
    of: find.widgetWithText(SwitchListTile, title),
    matching: find.byType(Switch),
  );

  Future<void> save(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.widgetWithText(FilledButton, 'Save').hitTestable());
    await tester.pumpAndSettle();
  }

  testWidgets('safety clear drops allowlist and preserves unrelated edits', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('safety.appAllowlist', 'safari,notes');
    await prefs.setBool('safety.enabled', false);
    await open(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Base URL'),
      'http://fresh.local/v1',
    );
    await clearStore(tester, 'Safety gate toggle and app allowlist');
    expect(tester.widget<Switch>(switchFor('Safety gate')).value, isTrue);
    expect(find.text('safari, notes'), findsNothing);
    await save(tester);
    expect(prefs.getString('safety.appAllowlist'), '');
    expect(prefs.getBool('safety.enabled'), isTrue);
    expect(prefs.getString('brain.baseUrl'), 'http://fresh.local/v1');
  });

  testWidgets('unsaved pause is dropped by safety clear', (tester) async {
    await open(tester);
    await tester.tap(switchFor('Safety gate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause 15 min'));
    await tester.pumpAndSettle();
    await clearStore(tester, 'Safety gate toggle and app allowlist');
    expect(tester.widget<Switch>(switchFor('Safety gate')).value, isTrue);
    await save(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('safety.enabled'), isTrue);
    expect(prefs.getInt('safety.resumeAtMs'), isNull);
  });

  testWidgets('perf clear keeps overlay off after save', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('perf_overlay_enabled', true);
    await open(tester);
    await clearStore(tester, 'Performance samples and overlay preference');
    expect(prefs.getBool('perf_overlay_enabled'), isNull);
    expect(find.text('perf cleared'), findsOneWidget);
    expect(find.textContaining('Could not delete local data'), findsNothing);
    await save(tester);
    expect(prefs.getBool('perf_overlay_enabled'), isFalse);
  });

  for (final field in ['allowlist', 'gate', 'overlay', 'localOnly']) {
    testWidgets('entered old $field initial read cannot restore after clear', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('safety.appAllowlist', 'safari');
      await prefs.setBool('safety.enabled', false);
      await prefs.setBool('perf_overlay_enabled', true);
      await prefs.setBool('privacy.localOnly', true);
      final release = Completer<void>();
      final entered = Completer<void>();
      var first = true;
      SettingsScreen.debugReadField = (name, read) async {
        final result = await read();
        if (name == field && first) {
          first = false;
          entered.complete();
          await release.future;
        }
        return result;
      };
      await open(tester);
      expect(entered.isCompleted, isTrue);
      final title = field == 'overlay'
          ? 'Performance samples and overlay preference'
          : field == 'localOnly'
          ? 'Local-only mode toggle'
          : 'Safety gate toggle and app allowlist';
      await clearStore(tester, title);
      release.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      if (field == 'allowlist' || field == 'gate') {
        expect(find.text('safari'), findsNothing);
        expect(tester.widget<Switch>(switchFor('Safety gate')).value, isTrue);
      }
      await save(tester);
      if (field == 'overlay') {
        expect(prefs.getBool('perf_overlay_enabled'), isFalse);
      }
      if (field == 'allowlist') {
        expect(prefs.getString('safety.appAllowlist'), '');
      }
      if (field == 'gate') expect(prefs.getBool('safety.enabled'), isTrue);
      if (field == 'localOnly') {
        expect(prefs.getBool('privacy.localOnly'), isNull);
      }
    });
  }

  testWidgets(
    'entered reload disables Save, failure requires explicit recovery',
    (tester) async {
      await open(tester);
      final release = Completer<void>();
      var fail = true;
      SettingsScreen.debugReadField = (name, read) async {
        if (name == 'overlay' && fail) {
          await release.future;
          throw StateError('private-storage-detail');
        }
        return read();
      };
      final tile = find.widgetWithText(
        ListTile,
        'Performance samples and overlay preference',
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
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      release.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not reload settings.'), findsOneWidget);
      expect(find.textContaining('private-storage-detail'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      fail = false;
      await clearStore(tester, 'Performance samples and overlay preference');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNotNull,
      );
      await save(tester);
    },
  );
  testWidgets('new allowlist and pause after clear are saved normally', (
    tester,
  ) async {
    await open(tester);
    await clearStore(tester, 'Safety gate toggle and app allowlist');
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'App allowlist (comma separated, empty = all)',
      ),
      'fresh, notes',
    );
    await tester.tap(switchFor('Safety gate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause 15 min'));
    await tester.pumpAndSettle();
    await save(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('safety.appAllowlist'), 'fresh,notes');
    expect(prefs.getBool('safety.enabled'), isFalse);
    expect(prefs.getInt('safety.resumeAtMs'), isNotNull);
  });

  testWidgets('new overlay choice after clear is saved normally', (
    tester,
  ) async {
    await open(tester);
    await clearStore(tester, 'Performance samples and overlay preference');
    await tester.tap(switchFor('Performance overlay'));
    await save(tester);
    expect(
      (await SharedPreferences.getInstance()).getBool('perf_overlay_enabled'),
      isTrue,
    );
  });
}
