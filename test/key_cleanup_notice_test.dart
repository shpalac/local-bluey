import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/key_cleanup_caller.dart';
import 'package:local_bluey/services/key_recording_intent.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/host_reload_controller.dart';
import 'package:local_bluey/services/hold_key_caller.dart';
import 'package:local_bluey/ui/key_cleanup_notice.dart';
import 'package:local_bluey/ui/mac_notice_region.dart';
import 'package:local_bluey/ui/host_reload_notice.dart';
import 'package:local_bluey/ui/hold_key_caller_notice.dart';
import 'package:local_bluey/ui/face_screen.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/onboarding_screen.dart';
import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/services/first_success.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'key_recording_intent_test.dart' show Fixture;

class _Checker extends PermissionChecker {
  @override
  Future<bool> accessibility() async => false;
  @override
  Future<bool> screenRecording() async => false;
  @override
  Future<bool> microphone() async => false;
  @override
  Future<bool> localNetwork() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [320.0, 1000.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final hebrew in [false, true]) {
        for (final dark in [false, true]) {
          for (final onboarding in [false, true]) {
            final name =
                '${width.toInt()}-${scale.toInt()}-${hebrew ? 'he' : 'en'}-${dark ? 'dark' : 'light'}-${onboarding ? 'onboard' : 'normal'}';
            testWidgets('actual notice tap composed $name', (tester) async {
              SharedPreferences.setMockInitialValues({});
              final f = Fixture();
              await tester.runAsync(f.init);
              final c = KeyCleanupCaller(
                owner: f.owner,
                allowed: () => f.allowed,
              );
              final host = HostReloadController(
                reload: () async {
                  throw StateError('private');
                },
              );
              final hold = HoldKeyCaller.operations(
                load: () async {},
                close: () async {},
                sync: () async {
                  throw StateError('private');
                },
              );
              addTearDown(() async {
                c.dispose();
                host.dispose();
                hold.dispose();
                await tester.runAsync(f.finish);
                Strings.uiLanguage = UiLanguage.system;
              });
              tester.view.physicalSize = Size(width, 900);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              Strings.uiLanguage = hebrew
                  ? UiLanguage.hebrew
                  : UiLanguage.english;
              var theme = ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              );
              {
                final font = FontLoader('BlueyRoboto')
                  ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
                await font.load();
                if (Platform.environment['KEY_CLEANUP_PIXELS'] == '1') {
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
                if (Platform.environment['KEY_CLEANUP_PIXELS'] == '1') {
                  final hebrewFont = FontLoader('BlueyHebrew')
                    ..addFont(
                      Future.value(
                        ByteData.sublistView(
                          File(
                            '/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf',
                          ).readAsBytesSync(),
                        ),
                      ),
                    );
                  await hebrewFont.load();
                }
                theme = theme.copyWith(
                  textTheme: theme.textTheme.apply(
                    fontFamily: 'BlueyRoboto',
                    fontFamilyFallback: ['BlueyHebrew'],
                  ),
                );
              }
              f.driver.partialStart = true;
              await tester.runAsync(
                () => expectLater(
                  f.owner.start(),
                  throwsA(isA<KeyRecordingException>()),
                ),
              );
              f.driver.partialStart = false;
              await host.reload();
              await hold.loadAndSync();
              final boundary = GlobalKey();
              final notices = [
                HostReloadNotice(controller: host),
                HoldKeyCallerNotice(caller: hold),
                KeyCleanupNotice(caller: c),
              ];
              var settingsTaps = 0,
                  closeTaps = 0,
                  permissionTaps = 0,
                  wakeTaps = 0;
              final controls = Wrap(
                children: [
                  TextButton(
                    onPressed: () {
                      settingsTaps++;
                    },
                    child: const Text('Settings'),
                  ),
                  TextButton(
                    onPressed: () {
                      closeTaps++;
                    },
                    child: const Text('Close'),
                  ),
                ],
              );
              await tester.pumpWidget(
                MaterialApp(
                  theme: theme,
                  home: Directionality(
                    textDirection: hebrew
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: MediaQuery(
                      data: MediaQueryData(
                        size: Size(width, 900),
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: RepaintBoundary(
                        key: boundary,
                        child: Scaffold(
                          body: onboarding
                              ? Column(
                                  children: [
                                    MacNoticeRegion(children: notices),
                                    Expanded(
                                      child: OnboardingScreen(
                                        checker: _Checker(),
                                        readiness: () async => (
                                          ServiceReadiness.ready,
                                          ServiceReadiness.ready,
                                        ),
                                        onDone: () {},
                                      ),
                                    ),
                                  ],
                                )
                              : FaceScreen(
                                  face: FaceState(),
                                  awake: false,
                                  bubble: 'Independent request bubble',
                                  onWakeChanged: (_) {
                                    wakeTaps++;
                                  },
                                ),
                          bottomNavigationBar: onboarding
                              ? null
                              : MacNoticeRegion(
                                  children: [
                                    ...notices,
                                    const MaterialBanner(
                                      content: Text(
                                        'Cloud provider active - data leaves this Mac.',
                                      ),
                                      actions: [SizedBox.shrink()],
                                    ),
                                    MaterialBanner(
                                      content: const Text(
                                        'Local Bluey needs Accessibility permission to point and click.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            permissionTaps++;
                                          },
                                          child: const Text('Open settings'),
                                        ),
                                      ],
                                    ),
                                    controls,
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              Future<void> shot(String state) async {
                if (Platform.environment['KEY_CLEANUP_PIXELS'] != '1') return;
                await tester.pump();
                await tester.runAsync(() async {
                  final image =
                      await (boundary.currentContext!.findRenderObject()!
                              as RenderRepaintBoundary)
                          .toImage();
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await File('/tmp/421-$name-$state.png')
                      .writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }

              await shot('error-top');
              for (final type in [HostReloadNotice, HoldKeyCallerNotice]) {
                final action = find.descendant(
                  of: find.byType(type),
                  matching: find.widgetWithText(TextButton, 'Retry'),
                );
                await tester.ensureVisible(action);
                await tester.tap(action);
                await tester.pumpAndSettle();
              }
              if (!onboarding) {
                await tester.ensureVisible(find.text('Open settings'));
                await tester.pumpAndSettle();
                await tester.tap(find.text('Open settings'));
                await shot('error-bottom');
              }
              if (!onboarding) {
                await tester.tap(find.text('Settings'));
                await tester.tap(find.text('Close'));
              } else {
                final check = find.text(hebrew ? 'בדוק שוב' : 'Check again');
                await tester.ensureVisible(check);
                await tester.tap(check);
                await tester.pumpAndSettle();
              }
              final retry = find.text(
                hebrew ? 'ניסיון ניקוי חוזר' : 'Retry cleanup',
              );
              await tester.ensureVisible(retry);
              await tester.pumpAndSettle();
              await Scrollable.ensureVisible(
                tester.element(find.byType(KeyCleanupNotice)),
                alignment: 0,
              );
              await tester.pumpAndSettle();
              await shot('error-key-top');
              await tester.ensureVisible(retry);
              await tester.pumpAndSettle();
              await shot('error-key');
              expect(
                tester.getRect(find.byType(MacNoticeRegion)).height,
                lessThanOrEqualTo(405),
              );
              f.driver.fail = 'stop';
              await tester.tap(retry);
              for (var i = 0; i < 6; i++) {
                await tester.pump();
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 20)),
                );
              }
              expect(c.failed, true);
              expect(c.enabled, true);
              expect(find.textContaining('private'), findsNothing);
              await shot('retry-error');
              f.driver.fail = null;
              f.driver.hold = 'stop';
              await tester.tap(retry);
              for (var i = 0; i < 6 && !f.driver.entered.isCompleted; i++) {
                await tester.pump();
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 20)),
                );
              }
              await tester.pump();
              expect(f.driver.entered.isCompleted, true);
              expect(c.loading, true);
              expect(
                tester
                    .widget<TextButton>(
                      find
                          .widgetWithText(
                            TextButton,
                            hebrew ? 'מנסה שוב...' : 'Retrying...',
                          )
                          .last,
                    )
                    .onPressed,
                isNull,
              );
              expect(tester.takeException(), isNull);
              await shot('pending');
              f.driver.release.complete();
              for (var i = 0; i < 6 && c.loading; i++) {
                await tester.pump();
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 20)),
                );
              }
              await tester.pumpAndSettle();
              expect(c.visible, false);
              expect(find.byType(KeyCleanupNotice), findsOneWidget);
              expect(f.delivered, isEmpty);
              expect(wakeTaps, 0);
              if (!onboarding) {
                expect(settingsTaps, 1);
                expect(closeTaps, 1);
                expect(permissionTaps, 1);
              }
              expect(tester.takeException(), isNull);
              await shot('success');
              await tester.pumpWidget(const SizedBox.shrink());
            });
          }
        }
      }
    }
  }
}
