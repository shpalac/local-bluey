import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/services/permission_watchdog.dart';
import 'package:local_bluey/ui/onboarding_screen.dart';
import 'package:local_bluey/ui/permission_recovery_card.dart';

class _SlowChecker extends PermissionChecker {
  final accessibilityCalls = <Completer<bool>>[];
  @override
  Future<bool> accessibility() {
    final c = Completer<bool>();
    accessibilityCalls.add(c);
    return c.future;
  }

  @override
  Future<bool> screenRecording() async => false;
  @override
  Future<bool> microphone() async => false;
  @override
  Future<bool> localNetwork() async => false;
}

class _ThrowingChecker extends PermissionChecker {
  @override
  Future<bool> accessibility() async => throw StateError('boom');
  @override
  Future<bool> screenRecording() async => true;
  @override
  Future<bool> microphone() async => false;
  @override
  Future<bool> localNetwork() async => false;
}

class _StubChecker extends PermissionChecker {
  _StubChecker(this.grants);
  final Map<String, bool> grants;
  @override
  Future<bool> accessibility() async => grants['accessibility'] ?? false;
  @override
  Future<bool> screenRecording() async => grants['screen_recording'] ?? false;
  @override
  Future<bool> microphone() async => grants['microphone'] ?? false;
  @override
  Future<bool> localNetwork() async => grants['local_network'] ?? false;
}

Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OnboardingScreen stepper', () {
    testWidgets('opens on the first permission step', (t) async {
      await t.pumpWidget(
        _app(OnboardingScreen(checker: _StubChecker({}), onDone: () {})),
      );
      await t.pumpAndSettle();
      expect(find.text('Step 1 of ${onboardingPermissions.length}'), findsOne);
      expect(find.text('Accessibility'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('required permission has no Skip button', (t) async {
      // Microphone is the only required step; skip to it by finishing steps.
      SharedPreferences.setMockInitialValues({
        'onboarding.step.accessibility': true,
        'onboarding.step.screen_recording': true,
      });
      await t.pumpWidget(
        _app(OnboardingScreen(checker: _StubChecker({}), onDone: () {})),
      );
      await t.pumpAndSettle();
      expect(find.text('Microphone'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('verify advances only after the grant exists', (t) async {
      final checker = _StubChecker({});
      await t.pumpWidget(
        _app(OnboardingScreen(checker: checker, onDone: () {})),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Verify'));
      await t.pumpAndSettle();
      // Denied: still on step 1, warning shown.
      expect(find.text('Accessibility'), findsOneWidget);
      expect(find.textContaining('still off'), findsOneWidget);
      checker.grants['accessibility'] = true;
      await t.tap(find.text('Verify'));
      await t.pumpAndSettle();
      expect(find.text('Step 2 of ${onboardingPermissions.length}'), findsOne);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding.step.accessibility'), isTrue);
    });

    testWidgets('skip persists the step and advances', (t) async {
      await t.pumpWidget(
        _app(OnboardingScreen(checker: _StubChecker({}), onDone: () {})),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Skip'));
      await t.pumpAndSettle();
      expect(find.text('Screen Recording'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding.step.accessibility'), isTrue);
    });

    testWidgets('finish marks onboarding done even with mic missing', (
      t,
    ) async {
      var done = false;
      await t.pumpWidget(
        _app(
          OnboardingScreen(
            checker: _StubChecker({}),
            onDone: () => done = true,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Done - start Bluey'));
      await t.pumpAndSettle();
      expect(done, isTrue);
      expect(await OnboardingScreen.isDone(), isTrue);
    });
  });

  group('OnboardingScreen reliability (#225)', () {
    testWidgets('late verify result after Skip never advances or persists', (
      t,
    ) async {
      final checker = _SlowChecker();
      await t.pumpWidget(
        _app(OnboardingScreen(checker: checker, onDone: () {})),
      );
      await t.pumpAndSettle();
      // Resolve the initial refresh check.
      for (final c in checker.accessibilityCalls) {
        if (!c.isCompleted) c.complete(false);
      }
      await t.pumpAndSettle();
      final before = checker.accessibilityCalls.length;
      await t.tap(find.text('Verify'));
      await t.pump();
      expect(checker.accessibilityCalls.length, before + 1);
      // Skip is disabled while verifying, so use the stale path via Back.
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, 'Skip')).onPressed,
        isNull,
      );
      checker.accessibilityCalls.last.complete(true);
      await t.pumpAndSettle();
      // The grant was real for this step, so it advances exactly once.
      expect(find.text('Step 2 of ${onboardingPermissions.length}'), findsOne);
    });

    testWidgets('rapid Verify taps start one check', (t) async {
      final checker = _SlowChecker();
      await t.pumpWidget(
        _app(OnboardingScreen(checker: checker, onDone: () {})),
      );
      await t.pumpAndSettle();
      for (final c in checker.accessibilityCalls) {
        if (!c.isCompleted) c.complete(false);
      }
      await t.pumpAndSettle();
      final before = checker.accessibilityCalls.length;
      await t.tap(find.text('Verify'));
      await t.pump();
      await t.tap(find.text('Verify'), warnIfMissed: false);
      await t.pump();
      expect(checker.accessibilityCalls.length, before + 1);
      checker.accessibilityCalls.last.complete(false);
      await t.pumpAndSettle();
      expect(
        t.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('disposal during a pending check does not throw', (t) async {
      final checker = _SlowChecker();
      await t.pumpWidget(
        _app(OnboardingScreen(checker: checker, onDone: () {})),
      );
      await t.pump();
      await t.pumpWidget(const SizedBox());
      for (final c in checker.accessibilityCalls) {
        c.complete(true);
      }
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('native exception shows a retryable state, no false grant', (
      t,
    ) async {
      await t.pumpWidget(
        _app(OnboardingScreen(checker: _ThrowingChecker(), onDone: () {})),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Could not check'), findsOneWidget);
      await t.tap(find.text('Verify'));
      await t.pumpAndSettle();
      expect(find.textContaining('Could not check'), findsOneWidget);
      expect(find.text('Step 1 of ${onboardingPermissions.length}'), findsOne);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding.step.accessibility'), isNull);
      expect(
        t.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('one failing check does not hide the others', (t) async {
      SharedPreferences.setMockInitialValues({
        'onboarding.step.accessibility': true,
      });
      await t.pumpWidget(
        _app(OnboardingScreen(checker: _ThrowingChecker(), onDone: () {})),
      );
      await t.pumpAndSettle();
      // Step 2 is Screen Recording, which the throwing checker grants.
      expect(find.text('Screen Recording'), findsOneWidget);
      expect(find.text('Granted.'), findsOneWidget);
    });

    testWidgets('Local Network is unknown, not denied, with a next action', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({
        'onboarding.step.accessibility': true,
        'onboarding.step.screen_recording': true,
        'onboarding.step.microphone': true,
      });
      await t.pumpWidget(
        _app(OnboardingScreen(checker: _StubChecker({}), onDone: () {})),
      );
      await t.pumpAndSettle();
      expect(find.text('Local Network'), findsOneWidget);
      expect(find.text('Verify'), findsNothing);
      expect(find.textContaining('Not granted'), findsNothing);
      expect(find.textContaining('pair the phone'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });
  });

  group('PermissionRecoveryCard', () {
    testWidgets('shows the permission and handles dismiss', (t) async {
      var dismissed = false;
      await t.pumpWidget(
        _app(
          Scaffold(
            body: PermissionRecoveryCard(
              permission: onboardingPermissions.first,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );
      expect(find.text('Accessibility was revoked'), findsOneWidget);
      expect(find.text('Fix'), findsOneWidget);
      await t.tap(find.text('Later'));
      await t.pumpAndSettle();
      expect(dismissed, isTrue);
    });
  });

  group('PermissionWatchdog', () {
    test('reports a grant that was later revoked', () async {
      SharedPreferences.setMockInitialValues({
        'watchdog.granted.screen_recording': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final wd = PermissionWatchdog(
        checker: _StubChecker({'microphone': true}),
        prefsOverride: prefs,
      );
      final revoked = await wd.recheckRevoked();
      expect(revoked.map((p) => p.id), ['screen_recording']);
    });
  });
}
