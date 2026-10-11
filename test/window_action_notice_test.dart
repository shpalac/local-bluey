import 'dart:io';
import 'dart:async';
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
import 'package:local_bluey/ui/permission_recovery_card.dart';
import 'package:local_bluey/ui/host_reload_notice.dart';
import 'package:local_bluey/ui/hold_key_caller_notice.dart';
import 'package:local_bluey/ui/face_screen.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/onboarding_screen.dart';
import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/services/first_success.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'key_recording_intent_test.dart' show Fixture;

import 'package:local_bluey/services/trust_observation.dart';
import 'package:local_bluey/ui/trust_observation_notice.dart';

import 'package:local_bluey/services/window_action_caller.dart';
import 'package:local_bluey/services/speech_mute_caller.dart';
import 'package:local_bluey/ui/speech_mute_notice.dart';
import 'package:local_bluey/ui/window_action_notice.dart';

import 'window_action_caller_test.dart' show WindowChannel;

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
            testWidgets('actual window action notice composed $name', (
              tester,
            ) async {
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
                if (Platform.environment['TRUST_PIXELS'] == '1') {
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
                if (Platform.environment['TRUST_PIXELS'] == '1') {
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
              final native = WindowChannel()..failing = 'show';
              const channel = MethodChannel('window_manager');
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                  .setMockMethodCallHandler(channel, native.handle);
              final window = WindowActionCaller();
              addTearDown(() {
                window.dispose();
                TestDefaultBinaryMessengerBinding
                    .instance
                    .defaultBinaryMessenger
                    .setMockMethodCallHandler(channel, null);
              });
              await tester.runAsync(() => window.request(WindowIntent.show));
              final trust = TrustObservation(read: () async => false);
              await tester.runAsync(trust.check);
              addTearDown(trust.dispose);
              final boundary = GlobalKey();
              final mute = SpeechMuteCaller.operations(() async {
                throw StateError('private');
              }, () {});
              await tester.runAsync(mute.mute);
              addTearDown(mute.dispose);
              final notices = [
                SpeechMuteNotice(caller: mute),
                HostReloadNotice(controller: host),
                HoldKeyCallerNotice(caller: hold),
                KeyCleanupNotice(caller: c),
                TrustObservationNotice(
                  caller: trust,
                  openSettings: () async {},
                ),
                WindowActionNotice(caller: window),
              ];
              var settingsTaps = 0,
                  closeTaps = 0,
                  wakeTaps = 0,
                  permissionTaps = 0;
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
                                    PermissionRecoveryCard(
                                      permission: onboardingPermissions[1],
                                      onDismiss: () {
                                        permissionTaps++;
                                      },
                                      fix: () async {
                                        permissionTaps++;
                                      },
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
                if (Platform.environment['TRUST_PIXELS'] != '1') return;
                await tester.pump();
                await tester.runAsync(() async {
                  final image =
                      await (boundary.currentContext!.findRenderObject()!
                              as RenderRepaintBoundary)
                          .toImage();
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await File('/tmp/441-$name-$state.png')
                      .writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }

              Future<void> focusNotice() async {
                await Scrollable.ensureVisible(
                  tester.element(find.byType(WindowActionNotice)),
                  alignment: 0,
                );
                await tester.pumpAndSettle();
              }

              await focusNotice();
              await shot('error-top');
              final retry = hebrew ? 'ניסיון הצגה חוזר' : 'Retry Show';
              await tester.ensureVisible(find.text(retry));
              await tester.pumpAndSettle();
              await shot('error-action');
              native.heldStep = 'show';
              await tester.runAsync(() => tester.tap(find.text(retry)));

              await tester.pump();
              await tester.runAsync(() => native.entered.future);
              final stopping = hebrew ? 'בהמתנה...' : 'Pending...';
              await focusNotice();
              await shot('pending-top');
              await tester.ensureVisible(find.text(stopping));
              await tester.pump();
              expect(
                tester
                    .widget<TextButton>(
                      find.widgetWithText(TextButton, stopping),
                    )
                    .onPressed,
                isNull,
              );
              await shot('pending-action');
              await tester.runAsync(() async {
                final settled = Completer<void>();
                void listen() {
                  if (!window.loading && !settled.isCompleted) {
                    settled.complete();
                  }
                }

                window.addListener(listen);
                native.released.complete();
                await settled.future;
                window.removeListener(listen);
              });
              await tester.pumpAndSettle();
              expect(window.failed, WindowIntent.show);
              native.failing = null;
              native.heldStep = null;
              await tester.ensureVisible(find.text(retry));
              await tester.runAsync(() async {
                final settled = Completer<void>();
                void listen() {
                  if (!window.loading && !settled.isCompleted) {
                    settled.complete();
                  }
                }

                window.addListener(listen);
                await tester.tap(find.text(retry));
                await settled.future;
                window.removeListener(listen);
              });
              await tester.pumpAndSettle();
              expect(window.visible, isFalse);
              expect(native.calls.where((m) => m == 'focus').length, 1);
              expect(native.calls.where((m) => m == 'show').length, 3);
              await shot('success');
              native.failing = 'hide';
              await tester.runAsync(() => window.request(WindowIntent.hide));
              await tester.pumpAndSettle();
              final hideRetry = hebrew ? 'ניסיון הסתרה חוזר' : 'Retry Hide';
              await tester.ensureVisible(find.text(hideRetry));
              await tester.pumpAndSettle();
              await shot('hide-error-action');
              expect(window.failed, WindowIntent.hide);
              native.failing = null;
              await tester.runAsync(() async {
                final settled = Completer<void>();
                void listen() {
                  if (!window.loading && !settled.isCompleted) {
                    settled.complete();
                  }
                }

                window.addListener(listen);
                await tester.tap(find.text(hideRetry));
                await settled.future;
                window.removeListener(listen);
              });
              await tester.pumpAndSettle();
              expect(window.visible, isFalse);
              expect(native.calls.where((m) => m == 'hide').length, 2);
              expect(native.calls.where((m) => m == 'focus').length, 1);
              expect(mute.failed, isTrue);
              // Other retained notices/actions remain reachable in the shared region.
              for (final type in [HostReloadNotice, HoldKeyCallerNotice]) {
                final action = find.descendant(
                  of: find.byType(type),
                  matching: find.widgetWithText(TextButton, 'Retry'),
                );
                await tester.ensureVisible(action);
                await tester.tap(action);
                await tester.pumpAndSettle();
              }
              final cleanup = find.text(
                hebrew ? 'ניסיון ניקוי חוזר' : 'Retry cleanup',
              );
              await tester.ensureVisible(cleanup);
              await tester.pumpAndSettle();
              expect(
                tester
                    .widget<TextButton>(
                      find.widgetWithText(
                        TextButton,
                        hebrew ? 'ניסיון ניקוי חוזר' : 'Retry cleanup',
                      ),
                    )
                    .onPressed,
                isNotNull,
              );
              expect(f.driver.starts, 1);
              expect(f.delivered, isEmpty);
              if (!onboarding) {
                await tester.ensureVisible(find.text('Settings'));
                await tester.tap(find.text('Settings'));
                await tester.tap(find.text('Close'));
                final dismiss = find.text(hebrew ? 'מאוחר יותר' : 'Later');
                await tester.ensureVisible(dismiss);
                await tester.pumpAndSettle();
                await tester.tap(dismiss);
                expect(permissionTaps, 1);
                expect(settingsTaps, 1);
                expect(closeTaps, 1);
              } else {
                final action = find.text(hebrew ? 'בדוק שוב' : 'Check again');
                await tester.ensureVisible(action);
                await tester.tap(action);
                await tester.pumpAndSettle();
              }
              expect(wakeTaps, 0);
              expect(
                tester.getRect(find.byType(MacNoticeRegion)).height,
                lessThanOrEqualTo(405),
              );
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            });
          }
        }
      }
    }
  }
}
