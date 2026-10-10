import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'registry clear refreshes both language fields, failed dropdown recovers',
    (tester) async {
      SharedPreferences.setMockInitialValues({'brain.model': 'fixture'});
      final stored = <String, String>{
        'ui.language': 'hebrew',
        'speech.language': 'he',
      };
      var fail = false;
      var failSpeechRemove = false;
      Completer<void>? writeEntered, writeRelease;
      final owner = LanguagePreferences(
        read: (key) async => stored[key],
        write: (key, value) async {
          if (writeEntered != null) {
            writeEntered.complete();
            await writeRelease!.future;
          }
          if (fail) throw StateError('private detail');
          stored[key] = value;
          return true;
        },
        remove: (key) async {
          if (failSpeechRemove && key == 'speech.language') return false;
          stored.remove(key);
          return true;
        },
      );
      Strings.debugOverride = owner;
      addTearDown(() => Strings.debugOverride = null);
      await owner.load();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      tester.view.physicalSize = const Size(1000, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      var theme = ThemeData();
      if (Platform.environment['LANGUAGE_PIXELS'] == '1') {
        final loader = FontLoader('BlueyRoboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
        await loader.load();
        final hebrew = FontLoader('NotoSansHebrew')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('test/screenshots/fonts/NotoSansHebrew-Regular.ttf')
                    .readAsBytesSync(),
              ),
            ),
          );
        await hebrew.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                ).readAsBytesSync(),
              ),
            ),
          );
        await icons.load();
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(
            fontFamily: 'BlueyRoboto',
            fontFamilyFallback: const ['NotoSansHebrew'],
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: RepaintBoundary(key: boundary, child: const SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      Finder uiField() => find.byType(DropdownButtonFormField<UiLanguage>);
      Finder speechField() => find.byType(DropdownButtonFormField<String>);
      UiLanguage? selectedUi() =>
          tester.state<FormFieldState<UiLanguage>>(uiField()).value;
      String? selectedSpeech() =>
          tester.state<FormFieldState<String>>(speechField()).value;
      expect(selectedUi(), UiLanguage.hebrew);
      expect(selectedSpeech(), 'he');
      final model = find.widgetWithText(TextFormField, 'Model');
      await tester.enterText(model, 'unsaved-model');
      final tile = find.widgetWithText(ListTile, 'העדפות שפת ממשק ודיבור');
      await tester.tap(
        find.descendant(of: tile, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      expect(stored, isEmpty);
      expect(selectedUi(), UiLanguage.system);
      expect(selectedSpeech(), 'auto');
      expect(find.text('unsaved-model'), findsOneWidget);
      Future<void> shot(String name) async {
        if (Platform.environment['LANGUAGE_PIXELS'] != '1') return;
        await tester.pump();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/375-$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await shot('cleared');
      fail = true;
      await tester.tap(uiField());
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(selectedUi(), UiLanguage.system);
      expect(stored, isEmpty);
      expect(
        find.text('Could not update language. Please retry.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await shot('failed');
      fail = false;
      await tester.tap(uiField());
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      await tester.tap(speechField());
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(selectedUi(), UiLanguage.english);
      expect(selectedSpeech(), 'en');
      expect(stored, {'ui.language': 'english', 'speech.language': 'en'});
      await shot('recovered');
      writeEntered = Completer<void>();
      writeRelease = Completer<void>();
      tester.widget<DropdownButtonFormField<UiLanguage>>(uiField()).onChanged!(
        UiLanguage.hebrew,
      );
      await tester.pump();
      expect(writeEntered.isCompleted, isTrue);
      final clearTile = find.widgetWithText(
        ListTile,
        'UI and speech language preferences',
      );
      await tester.tap(
        find.descendant(of: clearTile, matching: find.byType(IconButton)),
      );
      await tester.pump();
      writeRelease.complete();
      await tester.pumpAndSettle();
      expect(stored, isEmpty);
      expect(selectedUi(), UiLanguage.system);
      expect(selectedSpeech(), 'auto');
      expect(find.text('unsaved-model'), findsOneWidget);
      expect(tester.takeException(), isNull);
      writeEntered = null;
      writeRelease = null;
      await owner.setUiLanguage(UiLanguage.hebrew);
      await owner.setSpeechLanguage('he');
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(tester.element(uiField())).removeCurrentSnackBar();
      failSpeechRemove = true;
      final partialTile = find.widgetWithText(
        ListTile,
        'העדפות שפת ממשק ודיבור',
      );
      await tester.tap(
        find.descendant(of: partialTile, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      expect(stored, {'speech.language': 'he'});
      expect(selectedUi(), UiLanguage.system);
      expect(selectedSpeech(), 'he');
      expect(
        find.textContaining('Could not delete local data:'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      failSpeechRemove = false;
      final retryTile = find.widgetWithText(
        ListTile,
        'UI and speech language preferences',
      );
      await tester.tap(
        find.descendant(of: retryTile, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      expect(stored, isEmpty);
      expect(selectedUi(), UiLanguage.system);
      expect(selectedSpeech(), 'auto');
    },
  );
}
