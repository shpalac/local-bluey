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
import 'package:local_bluey/services/permission_observation.dart';
import 'package:local_bluey/services/permission_watchdog.dart';
import 'package:local_bluey/ui/permission_observation_notice.dart';

import 'permission_observation_test.dart' show Checker;

import 'package:local_bluey/ui/trust_observation_notice.dart';

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
            testWidgets('actual permission notice composed $name', (
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
                if (Platform.environment['PERMISSION_PIXELS'] == '1') {
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
                if (Platform.environment['PERMISSION_PIXELS'] == '1') {
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
              var checks = 0;
              final entered = Completer<void>(), release = Completer<bool>();
              final checker = Checker()..fail = 'accessibility';
              SharedPreferences.setMockInitialValues({
                'watchdog.granted.accessibility': true,
              });
              final wd = PermissionWatchdog(
                checker: checker,
                prefsOverride: await SharedPreferences.getInstance(),
              );
              final permissions = PermissionObservation(watchdog: wd);
              final trust = TrustObservation(
                read: () async => throw StateError('private'),
              );
              await trust.check();
              addTearDown(trust.dispose);
              addTearDown(permissions.dispose);
              final boundary = GlobalKey();
              final notices = [
                HostReloadNotice(controller: host),
                HoldKeyCallerNotice(caller: hold),
                KeyCleanupNotice(caller: c),
                PermissionObservationNotice(caller: permissions),
                TrustObservationNotice(
                  caller: trust,
                  openSettings: () async {},
                ),
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
                                    ListenableBuilder(
                                      listenable: permissions,
                                      builder: (context, _) =>
                                          permissions.revoked.isEmpty
                                          ? const SizedBox.shrink()
                                          : PermissionRecoveryCard(
                                              permission:
                                                  permissions.revoked.first,
                                              onDismiss: () {
                                                final id = permissions
                                                    .revoked
                                                    .first
                                                    .id;
                                                wd.clearBaseline(id);
                                                permissions.dismiss(id);
                                                permissionTaps++;
                                              },
                                              fix: () async {
                                                permissionTaps++;
                                              },
                                            ),
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
                if (Platform.environment['PERMISSION_PIXELS'] != '1') return;
                await tester.pump();
                await tester.runAsync(() async {
                  final image =
                      await (boundary.currentContext!.findRenderObject()!
                              as RenderRepaintBoundary)
                          .toImage();
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await File('/tmp/429-$name-$state.png')
                      .writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }

              Future<void> focusNotice() async {
                await Scrollable.ensureVisible(
                  tester.element(find.byType(PermissionObservationNotice)),
                  alignment: 0,
                );
                await tester.pumpAndSettle();
              }

              await focusNotice();
              await shot('unknown');
              Finder permissionText(String text) => find.descendant(
                of: find.byType(PermissionObservationNotice),
                matching: find.text(text),
              );
              final checkText = hebrew ? 'בדיקת מצב' : 'Check status';
              await tester.ensureVisible(permissionText(checkText));
              await tester.tap(permissionText(checkText));
              await tester.pumpAndSettle();
              expect(permissions.status, PermissionObservationStatus.failed);
              expect(permissions.revoked, isEmpty);
              expect(find.textContaining('private'), findsNothing);
              await focusNotice();
              await shot('error');
              checker.fail = null;
              await tester.ensureVisible(permissionText(checkText));
              await tester.tap(permissionText(checkText));
              await tester.pumpAndSettle();
              expect(permissions.status, PermissionObservationStatus.current);
              expect(permissions.revoked.single.id, 'accessibility');
              await shot('current-recovery');
              checker.fail = 'accessibility';
              await permissions.resume();
              await tester.pumpAndSettle();
              expect(permissions.status, PermissionObservationStatus.failed);
              expect(permissions.revoked.single.id, 'accessibility');
              await focusNotice();
              await shot('retained-error');
              checker.fail = null;
              checker.probe = (id) {
                checks++;
                if (id == 'accessibility') {
                  entered.complete();
                  return release.future;
                }
                return Future.value(true);
              };
              await tester.ensureVisible(permissionText(checkText));
              await tester.tap(permissionText(checkText));
              await tester.pump();
              await entered.future;
              final checking = permissionText(
                hebrew ? 'בודק...' : 'Checking...',
              );
              expect(
                tester
                    .widget<TextButton>(
                      find.widgetWithText(
                        TextButton,
                        hebrew ? 'בודק...' : 'Checking...',
                      ),
                    )
                    .onPressed,
                isNull,
              );
              expect(permissions.revoked.single.id, 'accessibility');
              await tester.ensureVisible(checking);
              await tester.pump();
              await shot('pending-retained');
              release.complete(true);
              await tester.pumpAndSettle();
              expect(permissions.status, PermissionObservationStatus.current);
              expect(permissions.revoked, isEmpty);
              expect(checks, 4);
              expect(permissionText(checkText), findsNothing);
              await shot('recovered');
              checker.probe = null;
              checker.grants.addAll({
                'accessibility': false,
                'screen_recording': true,
                'microphone': true,
                'local_network': true,
              });
              await permissions.resume();
              await tester.pumpAndSettle();
              expect(permissions.revoked.single.id, 'accessibility');
              checker.fail = 'accessibility';
              await permissions.resume();
              await tester.pumpAndSettle();
              await focusNotice();
              await shot('failed-after-recovery');
              final trustRetry = find.descendant(
                of: find.byType(TrustObservationNotice),
                matching: find.widgetWithText(TextButton, checkText),
              );
              await tester.ensureVisible(trustRetry);
              await tester.tap(trustRetry);
              await tester.pumpAndSettle();
              expect(trust.status, TrustObservationStatus.failed);
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
                final fix = find.text(hebrew ? 'תיקון' : 'Fix');
                await tester.ensureVisible(fix);
                await tester.pumpAndSettle();
                await tester.tap(fix);
                await tester.pumpAndSettle();
                expect(permissionTaps, 1);
                expect(permissions.revoked.single.id, 'accessibility');
                final dismiss = find.text(hebrew ? 'מאוחר יותר' : 'Later');
                await tester.ensureVisible(dismiss);
                await tester.pumpAndSettle();
                await tester.tap(dismiss);
                expect(permissionTaps, 2);
                expect(permissions.revoked, isEmpty);
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
