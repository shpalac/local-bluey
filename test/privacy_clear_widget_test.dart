import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'privacy registry clear, false/throw toggle and recovery stay honest',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'brain.model': 'fixture',
        'brain.baseUrl': 'https://remote.invalid/v1',
      });
      var calls = 0, records = 0;
      SettingsScreen.debugRecordTestEgress = (_) async {
        records++;
      };
      addTearDown(() => SettingsScreen.debugRecordTestEgress = null);
      SettingsScreen.debugTestChat = (_) async {
        calls++;
        return 'ok';
      };
      addTearDown(() => SettingsScreen.debugTestChat = null);
      bool? stored = true;
      var failWrite = false,
          throwWrite = false,
          failRead = false,
          failRemove = false;
      Completer<void>? writeEntered, writeRelease, readEntered, readRelease;
      final owner = LocalOnlyPreferences(
        read: () async {
          final value = stored;
          if (readEntered != null) {
            readEntered.complete();
            await readRelease!.future;
          }
          if (failRead) throw StateError('private read');
          return value;
        },
        write: (value) async {
          if (writeEntered != null) {
            writeEntered.complete();
            await writeRelease!.future;
          }
          if (failWrite) {
            if (throwWrite) throw StateError('private write');
            return false;
          }
          stored = value;
          return true;
        },
        remove: () async {
          if (failRemove) return false;
          stored = null;
          return true;
        },
      );
      PrivacyGuard.debugPreferences = owner;
      addTearDown(() => PrivacyGuard.debugPreferences = null);
      await owner.read();
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
      if (Platform.environment['PRIVACY_PIXELS'] == '1') {
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
      Finder tile() => find.widgetWithText(SwitchListTile, 'Local-only mode');
      Finder toggle() =>
          find.descendant(of: tile(), matching: find.byType(Switch));
      bool selected() => tester.widget<Switch>(toggle()).value;
      expect(selected(), true);
      final model = find.widgetWithText(TextFormField, 'Model');
      await tester.enterText(model, 'unsaved-model');
      final clearTile = find.widgetWithText(ListTile, 'Local-only mode toggle');
      await tester.tap(
        find.descendant(of: clearTile, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      expect(stored, isNull);
      expect(selected(), false);
      expect(find.text('unsaved-model'), findsOneWidget);
      Future<void> shot(String name) async {
        if (Platform.environment['PRIVACY_PIXELS'] != '1') return;
        await tester.pump();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/379-$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await shot('cleared');
      for (final throws in [false, true]) {
        failWrite = true;
        throwWrite = throws;
        await tester.tap(toggle());
        await tester.pumpAndSettle();
        expect(stored, isNull);
        expect(selected(), false);
        expect(
          find.text('Could not update local-only mode. Please retry.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      await shot('failed');
      failWrite = false;
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(stored, true);
      expect(selected(), true);
      await shot('recovered');
      writeEntered = Completer<void>();
      writeRelease = Completer<void>();
      tester.widget<SwitchListTile>(tile()).onChanged!(false);
      await tester.pump();
      expect(writeEntered.isCompleted, true);
      await tester.tap(
        find.descendant(of: clearTile, matching: find.byType(IconButton)),
      );
      await tester.pump();
      writeRelease.complete();
      await tester.pumpAndSettle();
      expect(stored, isNull);
      expect(selected(), false);
      expect(find.text('unsaved-model'), findsOneWidget);
      writeEntered = null;
      writeRelease = null;
      failRead = true;
      failWrite = true;
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(
        find.text('Local-only preference is unverified. Please retry.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      final recorded = records;
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(records, recorded);
      expect(
        find.text('Could not verify local-only mode. Please retry.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await shot('unverified');
      failRead = false;
      failWrite = false;
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(stored, true);
      expect(selected(), true);
      expect(
        find.text('Local-only preference is unverified. Please retry.'),
        findsNothing,
      );
      ScaffoldMessenger.of(tester.element(tile())).removeCurrentSnackBar();
      failRemove = true;
      await tester.tap(
        find.descendant(of: clearTile, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      expect(stored, true);
      expect(selected(), true);
      expect(
        find.textContaining('Could not delete local data:'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      failRemove = false;
      await tester.tap(
        find.descendant(of: clearTile, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      expect(stored, isNull);
      expect(selected(), false);
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(records, recorded + 1);
      expect(records, recorded + 1);
      expect(find.text('Connected: ok'), findsOneWidget);
      await shot('test-recovered');
      // Cached/default OFF must not authorize a stale entered source read.
      readEntered = Completer<void>();
      readRelease = Completer<void>();
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Test connection'),
          )
          .onPressed!();
      await tester.pump();
      expect(readEntered.isCompleted, true);
      final oldReadRelease = readRelease;
      readEntered = null;
      readRelease = null;
      final freshOn = owner.set(true);
      oldReadRelease.complete();
      await tester.pumpAndSettle();
      await freshOn;
      expect(calls, 1);
      expect(records, recorded + 1);
      expect(
        find.text('Could not verify local-only mode. Please retry.'),
        findsOneWidget,
      );
      // Fresh intent during entered egress blocks provider at the second read.
      await owner.set(false);
      await tester.pumpAndSettle();
      final egressEntered = Completer<void>(),
          egressRelease = Completer<void>();
      SettingsScreen.debugRecordTestEgress = (_) async {
        records++;
        egressEntered.complete();
        await egressRelease.future;
      };
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Test connection'),
          )
          .onPressed!();
      await tester.pump();
      expect(egressEntered.isCompleted, true);
      await owner.set(true);
      egressRelease.complete();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.textContaining('Blocked by Local-only mode:'),
        findsOneWidget,
      );
    },
  );
}
