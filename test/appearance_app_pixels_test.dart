import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/main.dart';
import 'package:local_bluey/services/appearance_startup.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/strings.dart';

void main() {
  for (final rtl in [false, true]) {
    testWidgets(
      'actual compact app top appearance notice/watch/route RTL=$rtl scale1.5',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final oldLanguage = Strings.uiLanguage;
        Strings.uiLanguage = rtl ? UiLanguage.hebrew : UiLanguage.english;
        addTearDown(() {
          Strings.uiLanguage = oldLanguage;
        });
        final oldWatch = ScreenWatch.instance;
        final watch = ScreenWatch.forTesting(
          localOnly: () async => true,
          allowlist: () async => ['Notes'],
          denylist: () async => [],
        );
        ScreenWatch.instance = watch;
        addTearDown(() {
          watch.dispose();
          ScreenWatch.instance = oldWatch;
        });
        expect(
          await watch.start(consentConfirmed: true),
          null,
        ); // Synthetic session, no observation pipeline.
        if (Platform.environment['APPEARANCE_APP_PIXELS'] == '1') {
          for (final family in [
            'Roboto',
            'Roboto_medium',
            'Arial',
            'sans-serif',
            'Ahem',
          ]) {
            final font = FontLoader(family)
              ..addFont(
                Future.value(
                  ByteData.sublistView(
                    File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
                        .readAsBytesSync(),
                  ),
                ),
              );
            await font.load();
          }
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
        }
        var fail = true;
        Completer<void>? entered, release;
        final c = AppearanceStartup(
          reload: () async {
            if (entered != null) {
              entered.complete();
              await release!.future;
            }
            if (fail) throw StateError('private');
          },
        );
        await c.reload();
        final boundary = GlobalKey();
        // LocalBlueyApp owns the actual builder placement, not a substitute Scaffold banner.
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: LocalBlueyApp(
              appearance: c,
              home: Builder(
                builder: (context) => Scaffold(
                  appBar: AppBar(
                    title: Text(rtl ? 'מסך בדיקה' : 'Synthetic route'),
                  ),
                  body: Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                              title: Text(
                                rtl ? 'מסך נעילה' : 'Synthetic lock route',
                              ),
                            ),
                            body: Center(
                              child: Text(
                                rtl
                                    ? 'תוכן מוגן נשמר'
                                    : 'Protected route content retained',
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: Text(rtl ? 'פתיחת מסך' : 'Open route'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(rtl ? 'פתיחת מסך' : 'Open route'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            rtl ? 'תוכן מוגן נשמר' : 'Protected route content retained',
          ),
          findsOneWidget,
        );
        expect(find.text(rtl ? 'עצירה' : 'Stop'), findsOneWidget);
        Future<void> shot(String name) async {
          if (Platform.environment['APPEARANCE_APP_PIXELS'] != '1') return;
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('/tmp/397-app-${rtl ? 'rtl' : 'en'}-$name.png')
                .writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        await shot('failure');
        fail = false;
        entered = Completer<void>();
        release = Completer<void>();
        await tester.tap(find.text(rtl ? 'ניסיון חוזר' : 'Retry'));
        await tester.pump();
        await tester.pump();
        expect(entered.isCompleted, true);
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(
                  TextButton,
                  rtl ? 'מנסה שוב...' : 'Retrying...',
                ),
              )
              .onPressed,
          isNull,
        );
        await shot('retry');
        release.complete();
        await tester.pumpAndSettle();
        expect(find.byType(MaterialBanner), findsNothing);
        expect(find.text(rtl ? 'עצירה' : 'Stop'), findsOneWidget);
        expect(
          find.text(
            rtl ? 'תוכן מוגן נשמר' : 'Protected route content retained',
          ),
          findsOneWidget,
        );
        await shot('recovery');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(rtl ? 'עצירה' : 'Stop'));
        await tester.pumpAndSettle();
        expect(watch.isActive, false);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
