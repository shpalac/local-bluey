import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/biometric_lock.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/ui/app_lock_tile.dart';
import 'package:local_bluey/ui/data_privacy_section.dart';
import 'package:local_bluey/ui/lock_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth implements Authenticator {
  AuthResult result = AuthResult.failed;
  Completer<AuthResult>? pending;
  int calls = 0;

  @override
  Future<AuthResult> authenticate({required String reason}) {
    calls++;
    return pending?.future ?? Future.value(result);
  }
}

Widget _app(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Directionality(
    textDirection: Strings.forceRtl ? TextDirection.rtl : TextDirection.ltr,
    child: child,
  ),
);

Widget _gate(BiometricLock lock) => _app(
  LockGate(
    lock: lock,
    reason: 'fixture',
    child: const Scaffold(body: Text('private content')),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Strings.uiLanguage = UiLanguage.english;
  });
  tearDown(() => Strings.uiLanguage = UiLanguage.system);

  testWidgets('enabled gate hides child on background and requires retry', (
    tester,
  ) async {
    final auth = _Auth()..result = AuthResult.success;
    final lock = BiometricLock.forTesting(authenticator: auth, enabled: true);
    await tester.pumpWidget(_gate(lock));
    await tester.pumpAndSettle();
    expect(find.text('private content'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // Paused disables scheduled frames. Force the requested widget rebuild
    // before inspecting the hidden child, without pretending it resumed.
    tester.binding.scheduleForcedFrame();
    await tester.pump();
    expect(find.text('private content'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('private content'), findsNothing);
    expect(auth.calls, 1);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(auth.calls, 2);
    expect(find.text('private content'), findsOneWidget);
  });

  testWidgets('auth sheet inactive/resume does not prompt again', (
    tester,
  ) async {
    final auth = _Auth()..pending = Completer<AuthResult>();
    final lock = BiometricLock.forTesting(authenticator: auth, enabled: true);
    await tester.pumpWidget(_gate(lock));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    auth.pending!.complete(AuthResult.success);
    await tester.pumpAndSettle();
    expect(auth.calls, 1);
    expect(find.text('private content'), findsOneWidget);
  });

  testWidgets('background invalidates in-flight success; no concurrent retry', (
    tester,
  ) async {
    final auth = _Auth()..pending = Completer<AuthResult>();
    final lock = BiometricLock.forTesting(authenticator: auth, enabled: true);
    await tester.pumpWidget(_gate(lock));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((widget) => widget is FilledButton),
          )
          .onPressed,
      isNull,
    );
    auth.pending!.complete(AuthResult.success);
    await tester.pumpAndSettle();
    expect(find.text('private content'), findsNothing);
    expect(auth.calls, 1);
    auth.pending = null;
    auth.result = AuthResult.success;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('private content'), findsOneWidget);
  });

  testWidgets('disposed gate ignores pending completion', (tester) async {
    final auth = _Auth()..pending = Completer<AuthResult>();
    await tester.pumpWidget(
      _gate(BiometricLock.forTesting(authenticator: auth, enabled: true)),
    );
    await tester.pumpWidget(_app(const Text('other')));
    auth.pending!.complete(AuthResult.success);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('private content'), findsNothing);
  });

  testWidgets('lock off never authenticates or relocks', (tester) async {
    final auth = _Auth();
    await tester.pumpWidget(
      _gate(BiometricLock.forTesting(authenticator: auth)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(auth.calls, 0);
    expect(find.text('private content'), findsOneWidget);
  });

  for (final language in [UiLanguage.english, UiLanguage.hebrew]) {
    for (final result in [
      AuthResult.failed,
      AuthResult.unavailable,
      AuthResult.error,
    ]) {
      testWidgets(
        '${language.name} ${result.name}: locked retry and enable failure',
        (tester) async {
          Strings.uiLanguage = language;
          final auth = _Auth()..result = result;
          final lock = BiometricLock.forTesting(
            authenticator: auth,
            enabled: true,
          );
          await tester.pumpWidget(_gate(lock));
          await tester.pumpAndSettle();
          expect(find.text('private content'), findsNothing);
          final button = language == UiLanguage.hebrew
              ? 'ביטול נעילה'
              : 'Unlock';
          expect(find.text(button), findsOneWidget);
          final guidance = switch (result) {
            AuthResult.unavailable =>
              language == UiLanguage.hebrew
                  ? 'אימות במכשיר לא הוגדר'
                  : 'Device authentication is not set up',
            AuthResult.error =>
              language == UiLanguage.hebrew
                  ? 'לא ניתן להתחיל באימות'
                  : 'Authentication could not start',
            _ =>
              language == UiLanguage.hebrew
                  ? 'האימות לא הושלם'
                  : 'Authentication was not completed',
          };
          expect(find.textContaining(guidance), findsOneWidget);
          auth.result = AuthResult.success;
          await tester.tap(find.text(button));
          await tester.pumpAndSettle();
          expect(find.text('private content'), findsOneWidget);
          auth.result = result;
          final off = BiometricLock.forTesting(authenticator: auth);
          await tester.pumpWidget(_app(Scaffold(body: AppLockTile(lock: off))));
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          expect(off.enabled, isFalse);
          expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
          expect(
            find.textContaining(
              language == UiLanguage.hebrew
                  ? result == AuthResult.error
                        ? 'לא ניתן לשמור'
                        : 'לא הופעלה'
                  : result == AuthResult.error
                  ? 'Could not save'
                  : 'was not enabled',
            ),
            findsOneWidget,
          );
        },
      );
    }
  }

  testWidgets('enabling waits for successful authentication and persistence', (
    tester,
  ) async {
    final auth = _Auth()..pending = Completer<AuthResult>();
    final lock = BiometricLock.forTesting(authenticator: auth);
    await tester.pumpWidget(_app(Scaffold(body: AppLockTile(lock: lock))));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(lock.enabled, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    auth.pending!.complete(AuthResult.success);
    await tester.pumpAndSettle();
    expect(lock.enabled, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool('lock.enabled'),
      isTrue,
    );
  });

  testWidgets('#363: clear updates the tile and drops a stale enable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'lock.enabled': true});
    final auth = _Auth();
    final lock = BiometricLock.forTesting(authenticator: auth);
    await lock.load();
    await tester.pumpWidget(_app(Scaffold(body: AppLockTile(lock: lock))));
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.runAsync(lock.clearPreference);
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(
      (await SharedPreferences.getInstance()).containsKey('lock.enabled'),
      isFalse,
    );
    // Entered enable, then clear, then old success released.
    auth.pending = Completer<AuthResult>();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.runAsync(lock.clearPreference);
    auth.pending!.complete(AuthResult.success);
    await tester.pumpAndSettle();
    expect(lock.enabled, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(
      (await SharedPreferences.getInstance()).containsKey('lock.enabled'),
      isFalse,
    );
    // Fresh enable needs a new successful authentication.
    auth.pending = null;
    auth.result = AuthResult.success;
    await tester.tap(find.byType(Switch));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(auth.calls, 2);
    expect(lock.enabled, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets(
    '#363: registry clear route reports failure safely and recovers',
    (tester) async {
      SharedPreferences.setMockInitialValues({'lock.enabled': true});
      final lock = BiometricLock.instance;
      final auth = _Auth()..result = AuthResult.success;
      lock.debugAuthenticator = auth;
      await tester.runAsync(lock.load);
      var fail = true;
      lock.debugStorage(
        remove: () async {
          if (fail) throw StateError('secret path /private/prefs.plist');
          return (await SharedPreferences.getInstance()).remove('lock.enabled');
        },
      );
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  AppLockTile(lock: lock),
                  const DataPrivacySection(),
                ],
              ),
            ),
          ),
        ),
      );
      final row = find.widgetWithText(ListTile, 'App-lock on/off preference');
      final clear = find.descendant(of: row, matching: find.byType(IconButton));
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining('secret'), findsNothing);
      expect(
        find.textContaining('Could not delete local data'),
        findsOneWidget,
      );
      expect(lock.enabled, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool('lock.enabled'),
        isTrue,
        reason: 'preference retained after failed removal',
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      fail = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(clear);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(lock.enabled, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(
        (await SharedPreferences.getInstance()).containsKey('lock.enabled'),
        isFalse,
      );

      // Fresh enable on the same service needs new successful authentication.
      final before = auth.calls;
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(auth.calls, before + 1);
      expect(lock.enabled, isTrue);
      lock.debugStorage();
      await tester.runAsync(lock.clearPreference);
    },
  );

  // CI opt-in captures rendered pixels, not DOM/text approximations.
  // Run with --dart-define=LOCK_CAPTURE_DIR=build/lock-captures, upload PNGs,
  // and inspect them before claiming English/Hebrew visual acceptance.
  const captureDir = String.fromEnvironment('LOCK_CAPTURE_DIR');
  for (final language in [UiLanguage.english, UiLanguage.hebrew]) {
    for (final result in [
      null,
      ...AuthResult.values.where((r) => r != AuthResult.success),
    ]) {
      testWidgets('capture ${language.name}-${result?.name ?? 'pending'}', (
        tester,
      ) async {
        if (captureDir.isEmpty) return;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Strings.uiLanguage = language;
        // Flutter widget tests normally use Ahem; load a readable Hebrew-capable
        // font for actual-pixel inspection. CI can supply LOCK_CAPTURE_FONT.
        const fontPath = String.fromEnvironment(
          'LOCK_CAPTURE_FONT',
          defaultValue: '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        );
        await tester.runAsync(() async {
          final data = await File(fontPath).readAsBytes();
          final loader = FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(data)));
          await loader.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
        final key = GlobalKey();
        final auth = _Auth();
        if (result == null) {
          auth.pending = Completer<AuthResult>();
        } else {
          auth.result = result;
        }
        final lock = BiometricLock.forTesting(
          authenticator: auth,
          enabled: true,
        );
        await tester.pumpWidget(RepaintBoundary(key: key, child: _gate(lock)));
        if (result == null) {
          await tester.pump(const Duration(milliseconds: 100));
        } else {
          await tester.pumpAndSettle();
        }
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await Directory(captureDir).create(recursive: true);
          await File(
            '$captureDir/${language.name}-${result?.name ?? 'pending'}.png',
          ).writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      });
    }
  }

  // Rendered state of the #363 registry clear route: failure snackbar with the
  // switch still on, then recovery with the switch off. Synthetic prefs only.
  for (final language in [UiLanguage.english, UiLanguage.hebrew]) {
    testWidgets('capture #363 clear route ${language.name}', (tester) async {
      if (captureDir.isEmpty) return;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Strings.uiLanguage = language;
      const fontPath = String.fromEnvironment(
        'LOCK_CAPTURE_FONT',
        defaultValue: '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      );
      await tester.runAsync(() async {
        final data = await File(fontPath).readAsBytes();
        final loader = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(data)));
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      SharedPreferences.setMockInitialValues({'lock.enabled': true});
      final lock = BiometricLock.instance;
      lock.debugAuthenticator = _Auth()..result = AuthResult.success;
      await tester.runAsync(lock.load);
      var fail = true;
      lock.debugStorage(
        remove: () async {
          if (fail) throw StateError('synthetic removal failure');
          return (await SharedPreferences.getInstance()).remove('lock.enabled');
        },
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: _app(
            Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    AppLockTile(lock: lock),
                    const DataPrivacySection(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> shot(String name) async {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await Directory(captureDir).create(recursive: true);
          await File('$captureDir/${language.name}-clear-$name.png')
              .writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
      }

      final store = DataRegistry.stores.firstWhere(
        (s) => s.id == 'app_lock_pref',
      );
      final row = find.widgetWithText(
        ListTile,
        Strings.t(store.whatEn, store.whatHe),
      );
      final clear = find.descendant(of: row, matching: find.byType(IconButton));
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await shot('failed');
      fail = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(clear);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await shot('recovered');
      lock.debugStorage();
      await tester.runAsync(lock.clearPreference);
    });
  }
}
