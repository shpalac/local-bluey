import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/watch_policy.dart';
import 'package:local_bluey/ui/watch_screen.dart';
import 'package:local_bluey/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    if (Platform.environment['WATCH_CAPTURE'] != null) {
      final glyphs = await File(
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      ).readAsBytes();
      await (FontLoader(
        'Capture',
      )..addFont(Future.value(ByteData.sublistView(glyphs)))).load();
      final bytes = await File(
        '/tmp/flutter-local/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  for (final rtl in [false, true]) {
    testWidgets(
      'bound consent and disabled active additions ${rtl ? 'HE' : 'EN'}',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'privacy.localOnly': true,
          'watch.appAllowlist': ['notes'],
        });
        Strings.uiLanguage = rtl ? UiLanguage.hebrew : UiLanguage.english;
        final original = ScreenWatch.instance;
        final watch = ScreenWatch.forTesting();
        ScreenWatch.instance = watch;
        addTearDown(() {
          ScreenWatch.instance = original;
          watch.dispose();
          Strings.uiLanguage = UiLanguage.system;
        });
        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light().copyWith(
                textTheme: AppTheme.light().textTheme.apply(
                  fontFamily: Platform.environment['WATCH_CAPTURE'] != null
                      ? 'Capture'
                      : 'Roboto',
                  fontFamilyFallback: ['Capture'],
                ),
              ),
              builder: (context, child) => Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: child!,
              ),
              home: const WatchScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(rtl ? 'התחלת סשן' : 'Start a session'));
        await tester.pumpAndSettle();
        expect(find.textContaining('notes'), findsWidgets);
        Future<void> capture(String state) async {
          final root = Platform.environment['WATCH_CAPTURE'];
          if (root == null) return;
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$root/watch-${rtl ? 'he' : 'en'}-$state.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('consent');
        // An external policy write during the dialog must not silently broaden.
        await WatchPolicy.addToAllowlist('mail');
        await tester.tap(find.text(rtl ? 'התחל צפייה' : 'Start watching'));
        await tester.pumpAndSettle();
        expect(watch.isActive, isFalse);
        expect(find.textContaining('scope changed'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.tap(find.text(rtl ? 'התחלת סשן' : 'Start a session'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(rtl ? 'התחל צפייה' : 'Start watching'));
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(watch.isActive, isTrue);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
        final add = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.add_circle_outline),
        );
        expect(add.onPressed, isNull);
        for (final chip in tester.widgetList<ChoiceChip>(
          find.byType(ChoiceChip),
        )) {
          expect(chip.onSelected, isNull);
        }
        expect(find.text(rtl ? 'עצירה עכשיו' : 'Stop now'), findsOneWidget);
        await capture('active');
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.widgetWithIcon(IconButton, Icons.remove_circle_outline).first,
        );
        await tester.pump();
        await tester.pump();
        expect(watch.isActive, isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
