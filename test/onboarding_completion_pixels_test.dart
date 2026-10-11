import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/first_success.dart';
import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/ui/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Checker extends PermissionChecker {
  @override
  Future<bool> accessibility() async => false;
  @override
  Future<bool> screenRecording() async => false;
  @override
  Future<bool> microphone() async => true;
  @override
  Future<bool> localNetwork() async => false;
}

Future<(ServiceReadiness, ServiceReadiness)> _ready() async =>
    (ServiceReadiness.ready, ServiceReadiness.ready);

/// Opt-in capture: set TUTORIAL_PIXELS=1 and run this test file.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => OnboardingScreen.debugWriteDone = null);
  final pixels = Platform.environment['TUTORIAL_PIXELS'] == '1';
  for (final width in [320.0, 1000.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final he in [false, true]) {
        testWidgets(
          'completion states $width $scale $he',
          skip: !pixels && width < 400 && scale > 1,
          (t) async {
            t.view.physicalSize = Size(width, 900);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            final old = Strings.uiLanguage;
            Strings.uiLanguage = he ? UiLanguage.hebrew : UiLanguage.english;
            addTearDown(() => Strings.uiLanguage = old);
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
            final key = GlobalKey();
            final events = <String>[];
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
                home: OnboardingScreen(
                  readiness: _ready,
                  checker: _Checker(),
                  onDone: () => events.add('done'),
                  onPlan: (_) => events.add('plan'),
                ),
              ),
            );
            await t.pumpAndSettle();
            await t.ensureVisible(
              find.text(
                he ? 'סיים את ההגדרה מאוחר יותר' : 'Finish setup later',
              ),
            );
            await t.tap(
              find.text(
                he ? 'סיים את ההגדרה מאוחר יותר' : 'Finish setup later',
              ),
            );
            await t.pumpAndSettle();
            final start = find.text(he ? 'התחל עם בלואי' : 'Start Bluey');
            final label =
                '${width.toInt()}-${scale.toInt()}-${he ? 'he' : 'en'}';
            Future<void> shot(String state) async {
              await t.pump();
              final error = t.takeException();
              if (pixels) expect(error, isNull);
              if (!pixels) return;
              await t.runAsync(() async {
                final image =
                    await (key.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory('docs/evidence/issue-463')
                  ..createSync(recursive: true);
                await File('${dir.path}/$label-$state.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }

            var hold = Completer<bool>();
            OnboardingScreen.debugWriteDone = () => hold.future;
            await t.ensureVisible(start);
            await t.tap(start);
            await t.pump();
            await shot('pending');
            hold.complete(false);
            await t.pumpAndSettle();
            await t.ensureVisible(start);
            await shot('error');
            hold = Completer<bool>();
            await t.tap(start);
            await t.pump();
            await shot('retry-pending');
            hold.complete(true);
            await t.pumpAndSettle();
            expect(events, ['plan', 'done']);
            await shot('success');
          },
        );
      }
    }
  }
}
