import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/main.dart';
import 'package:local_bluey/services/appearance_startup.dart';
import 'package:local_bluey/services/character_startup.dart';
import 'package:local_bluey/services/language_startup.dart';
import 'package:local_bluey/ui/language_startup_notice.dart';
import 'package:local_bluey/ui/character_startup_notice.dart';
import 'package:local_bluey/ui/appearance_startup_notice.dart';

import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'actual shared language retry updates app RTL and independent notices',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(
        () => ThemeController.instance.setMode(ThemeMode.system),
      );
      var fail = false, ui = 'english', speech = 'he';
      final owner = LanguagePreferences(
        read: (key) async {
          if (fail) throw StateError('private');
          return key == 'ui.language' ? ui : speech;
        },
      );
      final old = Strings.debugOverride;
      Strings.debugOverride = owner;
      addTearDown(() {
        Strings.debugOverride = old;
        owner.dispose();
      });
      await owner.load();
      fail = true;
      final c = LanguageStartup();
      await c.reload();
      final character = CharacterStartup(
        reload: () async => throw StateError('private'),
        verified: () => false,
      );
      await character.reload();
      await tester.pumpWidget(
        LocalBlueyApp(
          language: c,
          character: character,
          home: const Scaffold(body: Text('Route stays')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.text('Route stays'))),
        TextDirection.ltr,
      );
      fail = false;
      ui = 'hebrew';
      speech = 'en';
      await tester.tap(
        find.descendant(
          of: find.byType(LanguageStartupNotice),
          matching: find.widgetWithText(TextButton, 'Retry'),
        ),
      );
      await tester.pumpAndSettle();
      expect(Strings.uiLanguage, UiLanguage.hebrew);
      expect(Strings.speechLanguage, 'en');
      expect(
        Directionality.of(tester.element(find.text('Route stays'))),
        TextDirection.rtl,
      );
      expect(find.textContaining('לא אומתה'), findsOneWidget);
      expect(character.failed, true);
      expect(c.failed, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final rtl in [false, true]) {
          testWidgets(
            'actual concurrent language/character/appearance app Stop/back RTL=$rtl scale=$scale dark=$dark width=$width',
            (tester) async {
              tester.view.physicalSize = Size(width, 844);
              tester.view.devicePixelRatio = 1;
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              addTearDown(tester.view.reset);
              addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue,
              );
              SharedPreferences.setMockInitialValues({});
              await tester.runAsync(
                () => ThemeController.instance.setMode(
                  dark ? ThemeMode.dark : ThemeMode.light,
                ),
              );
              addTearDown(
                () => tester.runAsync(
                  () => ThemeController.instance.setMode(ThemeMode.system),
                ),
              );
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
              if (Platform.environment['WATCH_APP_PIXELS'] != '1') {
                final defaultFont = FontLoader('Roboto')
                  ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
                await tester.runAsync(defaultFont.load);
              }
              if (Platform.environment['WATCH_APP_PIXELS'] == '1') {
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
                          File(
                            '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
                          ).readAsBytesSync(),
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
              var fail = false;
              Completer<void>? entered, release;
              final preferences = LanguagePreferences(
                read: (key) async {
                  if (entered != null && !entered.isCompleted) {
                    entered.complete();
                    await release!.future;
                  }
                  if (fail) throw StateError('private');
                  return key == 'ui.language'
                      ? (rtl ? 'hebrew' : 'english')
                      : 'he';
                },
                write: (_, _) async => true,
                remove: (_) async => true,
              );
              final oldPreferences = Strings.debugOverride;
              Strings.debugOverride = preferences;
              await preferences.load();
              addTearDown(() {
                Strings.debugOverride = oldPreferences;
                preferences.dispose();
              });
              final c = LanguageStartup();
              fail = true;
              await c.reload();
              final character = CharacterStartup(
                reload: () async => throw StateError('private'),
                verified: () => false,
              );
              await character.reload();
              final appearance = AppearanceStartup(
                reload: () async => throw StateError('private'),
              );
              await appearance.reload();
              final boundary = GlobalKey();
              // LocalBlueyApp owns the actual builder placement, not a substitute Scaffold banner.
              await tester.pumpWidget(
                RepaintBoundary(
                  key: boundary,
                  child: LocalBlueyApp(
                    appearance: appearance,
                    character: character,
                    language: c,
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
                                      rtl
                                          ? 'מסך נעילה'
                                          : 'Synthetic lock route',
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
                if (Platform.environment['WATCH_APP_PIXELS'] != '1') return;
                await tester.runAsync(() async {
                  final image =
                      await (boundary.currentContext!.findRenderObject()!
                              as RenderRepaintBoundary)
                          .toImage();
                  final data = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await File(
                    '/tmp/405-${width.toInt()}-${dark ? 'dark' : 'light'}-$scale-${rtl ? 'rtl' : 'en'}-$name.png',
                  ).writeAsBytes(data!.buffer.asUint8List());
                  image.dispose();
                });
              }

              void geometry() {
                final stopFinder = find.widgetWithText(
                  TextButton,
                  rtl ? 'עצירה' : 'Stop',
                );
                final stopRect = tester.getRect(stopFinder);
                expect(stopRect.width, greaterThanOrEqualTo(48));
                expect(stopRect.height, greaterThanOrEqualTo(48));
                final backRect = tester.getRect(find.byType(BackButton));
                expect(backRect.top, greaterThanOrEqualTo(stopRect.bottom));
                final background = dark
                    ? const Color(0xFF5F1414)
                    : const Color(0xFFFFEAEA);
                final foreground = dark
                    ? const Color(0xFFFFEAEA)
                    : const Color(0xFF5F1414);
                final button = tester.widget<TextButton>(stopFinder);
                expect(button.style!.foregroundColor!.resolve({}), foreground);
                expect(
                  AppTokens.contrastRatio(foreground, background),
                  greaterThanOrEqualTo(4.5),
                );
              }

              expect(
                Strings.uiLanguage,
                rtl ? UiLanguage.hebrew : UiLanguage.english,
              );
              expect(Strings.speechLanguage, 'he');
              expect(
                find.textContaining(
                  rtl ? 'לא אומתו' : 'saved values unverified',
                ),
                findsOneWidget,
              );
              geometry();
              await shot('failure');
              fail = false;
              entered = Completer<void>();
              release = Completer<void>();
              await tester.tap(
                find.descendant(
                  of: find.byType(LanguageStartupNotice),
                  matching: find.widgetWithText(
                    TextButton,
                    rtl ? 'ניסיון חוזר' : 'Retry',
                  ),
                ),
              );
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
              expect(find.byType(MaterialBanner), findsNWidgets(2));
              expect(find.byType(LanguageStartupNotice), findsOneWidget);
              expect(c.failed, false);
              expect(
                Strings.uiLanguage,
                rtl ? UiLanguage.hebrew : UiLanguage.english,
              );
              expect(Strings.speechLanguage, 'he');
              expect(find.text(rtl ? 'עצירה' : 'Stop'), findsOneWidget);
              expect(
                find.text(
                  rtl ? 'תוכן מוגן נשמר' : 'Protected route content retained',
                ),
                findsOneWidget,
              );
              geometry();
              await shot('recovery');
              for (final notice in [
                find.byType(CharacterStartupNotice),
                find.byType(AppearanceStartupNotice),
              ]) {
                final retry = find.descendant(
                  of: notice,
                  matching: find.widgetWithText(
                    TextButton,
                    rtl ? 'ניסיון חוזר' : 'Retry',
                  ),
                );
                expect(tester.widget<TextButton>(retry).onPressed, isNotNull);
                await tester.tap(retry);
                await tester.pumpAndSettle();
              }
              expect(character.failed, true);
              expect(appearance.failed, true);
              await tester.tap(find.byType(BackButton));
              await tester.pumpAndSettle();
              expect(
                find.text(rtl ? 'פתיחת מסך' : 'Open route'),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              await tester.tap(find.text(rtl ? 'עצירה' : 'Stop'));
              await tester.pumpAndSettle();
              expect(watch.isActive, false);
              await tester.pumpWidget(const SizedBox.shrink());
            },
          );
        }
      }
    }
  }
}
