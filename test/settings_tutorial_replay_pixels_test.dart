import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/tutorial.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store implements TutorialDoneStore {
  Completer<void>? hold;
  bool fail = false;
  @override
  Future<void> markDone() async {}
  @override
  Future<void> clear() async {
    await hold?.future;
    if (fail) throw StateError('private');
  }
}

/// Opt-in capture: set TUTORIAL_PIXELS=1 and run this test file.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [320.0, 1000.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final he in [false, true]) {
        testWidgets('replay tile states $width $scale $he', (t) async {
          t.view.physicalSize = Size(width, 900);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final old = Strings.uiLanguage;
          Strings.uiLanguage = he ? UiLanguage.hebrew : UiLanguage.english;
          addTearDown(() => Strings.uiLanguage = old);
          final pixels = Platform.environment['TUTORIAL_PIXELS'] == '1';
          var theme = ThemeData();
          if (pixels) {
            Future<void> font(String family, ByteData data) async {
              final l = FontLoader(family)..addFont(Future.value(data));
              await l.load();
            }

            await font(
              'BlueyRoboto',
              await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
            );
            await font(
              'BlueyHebrew',
              ByteData.sublistView(
                File(
                  '/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf',
                ).readAsBytesSync(),
              ),
            );
            await font(
              'MaterialIcons',
              ByteData.sublistView(
                File(
                  '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                ).readAsBytesSync(),
              ),
            );
            theme = theme.copyWith(
              textTheme: theme.textTheme.apply(
                fontFamily: 'BlueyRoboto',
                fontFamilyFallback: ['BlueyHebrew'],
              ),
            );
          }
          final store = _Store()..hold = Completer<void>();
          final c = TutorialController(store: store);
          addTearDown(c.dispose);
          final key = GlobalKey();
          await t.pumpWidget(
            MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                  textDirection: he ? TextDirection.rtl : TextDirection.ltr,
                  child: RepaintBoundary(key: key, child: child!),
                ),
              ),
              home: SettingsScreen(tutorial: c),
            ),
          );
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          await t.pump();
          final title = he
              ? 'הפעלה חוזרת של המדריך'
              : 'Replay first-steps tutorial';
          await t.scrollUntilVisible(
            find.text(title),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await t.ensureVisible(find.text(title));
          await t.pump();
          final label = '${width.toInt()}-${scale.toInt()}-${he ? 'he' : 'en'}';
          Future<void> shot(String state) async {
            await t.pump();
            // Other Settings rows overflow in the wide default test font; the
            // evidence run loads real fonts and must be clean.
            final error = t.takeException();
            if (pixels) expect(error, isNull);
            final tile = t.getRect(find.widgetWithText(ListTile, title));
            expect(tile.height, greaterThanOrEqualTo(48));
            if (!pixels) return;
            await t.runAsync(() async {
              final image =
                  await (key.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('docs/evidence/issue-464')
                ..createSync(recursive: true);
              await File('${dir.path}/$label-$state.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          store.fail = true;
          await t.tap(find.text(title));
          await t.pump();
          await shot('pending');
          store.hold!.complete();
          await t.pump();
          await t.pump();
          await shot('error');
          t
              .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
              .clearSnackBars();
        });
      }
    }
  }
}
