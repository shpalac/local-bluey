import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/hold_key.dart';
import 'package:local_bluey/services/hold_key_controller.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:local_bluey/ui/hold_key_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'disposed section contains entered setter error without late UI work',
    (t) async {
      final entered = Completer<void>(), release = Completer<void>();
      final c = HoldKeySettings(
        read: (_) async => null,
        write: (_, _) async {
          entered.complete();
          await release.future;
          throw StateError('private');
        },
        remove: (_) async => true,
      );
      HoldKeySettings.debugOverride = c;
      addTearDown(() {
        HoldKeySettings.debugOverride = null;
        c.dispose();
      });
      await c.load();
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: HoldKeySection())),
      );
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(entered.isCompleted, true);
      await t.pumpWidget(const SizedBox.shrink());
      release.complete();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'actual section toggle/dropdown failure recovery and registry refresh preserve unrelated edit',
    (t) async {
      final data = <String, Object>{};
      bool fail = true, readFail = false;
      Completer<void>? entered, release;
      final c = HoldKeySettings(
        read: (k) async {
          if (readFail) throw StateError('secret read');
          return data[k];
        },
        write: (k, v) async {
          if (entered != null) {
            entered.complete();
            await release!.future;
          }
          if (fail) throw StateError('private endpoint');
          data[k] = v;
          return true;
        },
        remove: (k) async {
          data.remove(k);
          return true;
        },
      );
      HoldKeySettings.debugOverride = c;
      addTearDown(() {
        HoldKeySettings.debugOverride = null;
        c.dispose();
      });
      await c.load();
      final text = TextEditingController(text: 'keep this edit');
      addTearDown(text.dispose);
      t.view.physicalSize = const Size(1000, 850);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var theme = ThemeData();
      if (Platform.environment['HOLD_PIXELS'] == '1') {
        final font = FontLoader('BlueyRoboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
        await font.load();
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
          textTheme: theme.textTheme.apply(fontFamily: 'BlueyRoboto'),
        );
      }
      final boundary = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Hold-to-talk settings fixture'),
              ),
              body: Column(
                children: [
                  const HoldKeySection(),
                  TextField(
                    controller: text,
                    decoration: const InputDecoration(
                      labelText: 'Unrelated synthetic edit',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Future<void> shot(String name) async {
        if (Platform.environment['HOLD_PIXELS'] != '1') return;
        await t.pump();
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/385-$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(c.enabled, false);
      expect(find.textContaining('Could not update'), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
      await shot('toggle-failure');
      fail = false;
      entered = Completer<void>();
      release = Completer<void>();
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(entered.isCompleted, true);
      expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(c.enabled, false);
      await shot('toggle-held');
      release.complete();
      await t.pumpAndSettle();
      entered = release = null;
      expect(c.enabled, true);
      expect(find.textContaining('Could not update'), findsNothing);
      await shot('toggle-recovery');
      fail = true;
      await t.tap(find.byType(DropdownButton<HoldKey>));
      await t.pumpAndSettle();
      await t.tap(find.text('Fn / Globe').last);
      await t.pumpAndSettle();
      expect(c.key, HoldKey.rightCommand);
      expect(find.textContaining('Could not update'), findsOneWidget);
      await shot('key-failure');
      fail = false;
      await t.tap(find.byType(DropdownButton<HoldKey>));
      await t.pumpAndSettle();
      await t.tap(find.text('Fn / Globe').last);
      await t.pumpAndSettle();
      expect(c.key, HoldKey.fn);
      fail = true;
      await t.tap(find.byType(DropdownButton<int>));
      await t.pumpAndSettle();
      await t.tap(find.text('600 ms').last);
      await t.pumpAndSettle();
      expect(c.thresholdMs, 400);
      expect(find.textContaining('Could not update'), findsOneWidget);
      await shot('threshold-failure');
      fail = false;
      await t.tap(find.byType(DropdownButton<int>));
      await t.pumpAndSettle();
      await t.tap(find.text('600 ms').last);
      await t.pumpAndSettle();
      expect(c.thresholdMs, 600);
      expect(find.textContaining('Could not update'), findsNothing);
      await shot('dropdown-recovery');
      readFail = true;
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(c.enabled, true);
      expect(c.verified, false);
      expect(find.textContaining('could not be verified'), findsOneWidget);
      await shot('uncertain');
      readFail = false;
      await c.load();
      await t.pumpAndSettle();
      expect(c.enabled, false);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(c.enabled, true);
      await DataRegistry.stores
          .firstWhere((s) => s.id == 'hold_key_pref')
          .clear();
      await t.pumpAndSettle();
      expect(c.enabled, false);
      expect(c.key, HoldKey.rightCommand);
      expect(c.thresholdMs, 400);
      expect(data, isEmpty);
      expect(text.text, 'keep this edit');
      expect(find.text('Key'), findsNothing);
      expect(find.textContaining('Could not update'), findsNothing);
      await shot('clear');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
