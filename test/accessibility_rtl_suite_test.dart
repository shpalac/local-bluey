import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/watch_suggestions.dart';
import 'package:local_bluey/ui/permission_recovery_card.dart';
import 'package:local_bluey/ui/watch_suggestion_card.dart';

// Fabricated callbacks only: no permission bridge, watcher, store or transport.
void main() {
  for (final rtl in [false, true]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'critical cards keyboard/semantics 320 ${rtl ? 'he' : 'en'} $dark $scale',
          (tester) async {
            final oldLanguage = Strings.uiLanguage;
            Strings.uiLanguage = rtl ? UiLanguage.hebrew : UiLanguage.english;
            addTearDown(() => Strings.uiLanguage = oldLanguage);
            tester.view.physicalSize = const Size(320, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final handle = tester.ensureSemantics();

            final gate = Completer<void>();
            try {
              var fixes = 0, later = 0, never = 0, dismiss = 0;
              final key = GlobalKey();
              final capture = Platform.environment['A11Y_CAPTURE'];
              if (capture != null) {
                final glyphs = File(
                  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
                ).readAsBytesSync();
                await (FontLoader(
                  'A11yCapture',
                )..addFont(Future.value(ByteData.sublistView(glyphs)))).load();
              }
              if (capture != null) {
                final icons = File(
                  '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                ).readAsBytesSync();
                await (FontLoader(
                  'MaterialIcons',
                )..addFont(Future.value(ByteData.sublistView(icons)))).load();
              }
              await tester.pumpWidget(
                RepaintBoundary(
                  key: key,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: ThemeData(
                      brightness: dark ? Brightness.dark : Brightness.light,
                      fontFamily: capture == null ? null : 'A11yCapture',
                    ),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: Directionality(
                        textDirection: rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: child!,
                      ),
                    ),
                    home: Scaffold(
                      body: SingleChildScrollView(
                        child: Column(
                          children: [
                            PermissionRecoveryCard(
                              permission: onboardingPermissions[2],
                              onDismiss: () => later++,
                              fix: () async {
                                fixes++;
                                await gate.future;
                                throw StateError('private-fixture');
                              },
                            ),
                            WatchSuggestionCard(
                              suggestion: WatchSuggestion(
                                reason: 'Synthetic reason',
                                evidence: 'Quoted fabricated evidence',
                                observedDetail: 'בדיקת דוגמה',
                                repeatCount: 3,
                                app: 'Notes',
                                at: DateTime(2026, 10, 11),
                              ),
                              onNeverForApp: () => never++,
                              onDismiss: () => dismiss++,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final fix = rtl ? 'תיקון' : 'Fix';
              final pending = rtl ? 'פותח הגדרות...' : 'Opening settings...';
              final laterText = rtl ? 'מאוחר יותר' : 'Later';
              final neverText = rtl ? 'לעולם לא עבור Notes' : 'Never for Notes';
              final dismissText = rtl ? 'סגירה' : 'Dismiss';
              Finder button(String label) =>
                  find.widgetWithText(TextButton, label);
              for (final label in [fix, laterText, neverText, dismissText]) {
                final node = tester.getSemantics(button(label));
                expect(
                  node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                  isTrue,
                );
                expect(node.getSemanticsData().label, contains(label));
              }
              // Real keyboard events through the existing Material focus traversal.
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pumpAndSettle();
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pump();
              expect(fixes, 1);
              expect(
                tester.widget<TextButton>(button(pending)).onPressed,
                isNull,
              );
              expect(
                tester
                    .getSemantics(button(pending))
                    .getSemanticsData()
                    .hasAction(ui.SemanticsAction.tap),
                isFalse,
              );
              // A disabled pending Fix is skipped, but Later remains keyboard reachable.
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pumpAndSettle();
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pump();
              expect(later, 1);
              expect(fixes, 1);
              gate.complete();
              await tester.pumpAndSettle();
              expect(
                tester.widget<TextButton>(button(fix)).onPressed,
                isNotNull,
              );
              expect(find.textContaining('private-fixture'), findsNothing);
              expect(
                find.text(
                  rtl
                      ? 'לא ניתן לפתוח את הגדרות ההרשאה. נסו שוב או פתחו את הגדרות המערכת.'
                      : 'Could not open permission settings. Try again or open System Settings.',
                ),
                findsOneWidget,
              );
              // Failure keeps explicit safe retry and the other card's actions.
              for (final label in [neverText, dismissText]) {
                await tester.ensureVisible(button(label));
                await tester.pumpAndSettle();
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.pumpAndSettle();
                await tester.sendKeyEvent(LogicalKeyboardKey.enter);
                await tester.pumpAndSettle();
              }
              expect(never, 1);
              expect(dismiss, 1);
              expect(fixes, 1);
              expect(tester.takeException(), isNull);
              expect(find.textContaining('בדיקת דוגמה'), findsOneWidget);
              if (capture != null) {
                for (final section in ['permission', 'suggestion']) {
                  if (section == 'permission') {
                    tester
                        .state<ScrollableState>(find.byType(Scrollable).first)
                        .position
                        .jumpTo(0);
                  } else {
                    await tester.ensureVisible(button(dismissText));
                  }
                  await tester.pumpAndSettle();
                  await tester.runAsync(() async {
                    final image =
                        await (key.currentContext!.findRenderObject()!
                                as RenderRepaintBoundary)
                            .toImage();
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    await File(
                      '$capture/${rtl ? 'he' : 'en'}-${dark ? 'dark' : 'light'}-${scale.toInt()}-$section.png',
                    ).writeAsBytes(bytes!.buffer.asUint8List());
                    image.dispose();
                  });
                }
              }
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
            } finally {
              if (!gate.isCompleted) gate.complete();
              await tester.pump();
              handle.dispose();
            }
          },
        );
      }
    }
  }
}
