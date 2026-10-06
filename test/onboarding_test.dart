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
      expect(find.byKey(const Key('step-accessibility')), findsOneWidget);
      expect(find.text('Accessibility'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Set up click control later'), findsOneWidget);
      expect(find.text('Done - start Bluey'), findsNothing);
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
      expect(find.textContaining('later'), findsOneWidget); // Finish only
      expect(find.text('Set up Microphone'), findsOneWidget); // heading
    });

    testWidgets('verify advances only after the grant exists', (t) async {
      final checker = _StubChecker({});
      await t.pumpWidget(
        _app(OnboardingScreen(checker: checker, onDone: () {})),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Check again'));
      await t.pumpAndSettle();
      // Denied: still on step 1, warning shown.
      expect(find.text('Accessibility'), findsOneWidget);
      expect(find.textContaining('still off'), findsOneWidget);
      checker.grants['accessibility'] = true;
      await t.tap(find.text('Check again'));
      await t.pumpAndSettle();
      // Granted: one primary action, Continue. No auto-advance.
      expect(find.text('Granted.'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text('Screen Recording'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding.step.accessibility'), isTrue);
      expect(prefs.getBool('onboarding.deferred.accessibility'), isFalse);
    });

    testWidgets('deferring is recorded separately from a grant', (t) async {
      await t.pumpWidget(
        _app(OnboardingScreen(checker: _StubChecker({}), onDone: () {})),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Set up click control later'));
      await t.pumpAndSettle();
      expect(find.text('Screen Recording'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding.step.accessibility'), isTrue);
      expect(prefs.getBool('onboarding.deferred.accessibility'), isTrue);
      // The overview shows deferred, not granted.
      expect(find.textContaining('Accessibility - later'), findsOneWidget);
      expect(find.textContaining('Accessibility - granted'), findsNothing);
    });

    testWidgets('a deferred step survives relaunch and can be revisited', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({
        'onboarding.step.accessibility': true,
        'onboarding.deferred.accessibility': true,
      });
      final checker = _StubChecker({});
      await t.pumpWidget(
        _app(OnboardingScreen(checker: checker, onDone: () {})),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Accessibility - later'), findsOneWidget);
      await t.tap(find.byKey(const Key('step-accessibility')));
      await t.pumpAndSettle();
      checker.grants['accessibility'] = true;
      await t.tap(find.text('Check again'));
      await t.pumpAndSettle();
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding.deferred.accessibility'), isFalse);
      expect(find.textContaining('Accessibility - granted'), findsOneWidget);
    });

    testWidgets('finish later shows what is off, then Start Bluey exits', (
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
      await t.ensureVisible(find.text('Finish setup later'));
      await t.tap(find.text('Finish setup later'));
      await t.pumpAndSettle();
      // Nothing is marked done until the user confirms the summary.
      expect(done, isFalse);
      expect(await OnboardingScreen.isDone(), isFalse);
      expect(find.textContaining('cannot hear you'), findsOneWidget);
      expect(
        find.textContaining('cannot see what is on your screen'),
        findsOne,
      );
      await t.tap(find.text('Start Bluey'));
      await t.pumpAndSettle();
      expect(done, isTrue);
      expect(await OnboardingScreen.isDone(), isTrue);
    });

    testWidgets('summary can go back to setup', (t) async {
      await t.pumpWidget(
        _app(OnboardingScreen(checker: _StubChecker({}), onDone: () {})),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Finish setup later'));
      await t.tap(find.text('Finish setup later'));
      await t.pumpAndSettle();
      await t.tap(find.text('Back to setup'));
      await t.pumpAndSettle();
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });

  group('OnboardingScreen reliability (#225)', () {
    testWidgets('late verify result never advances or persists on its own', (
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
      await t.tap(find.text('Check again'));
      await t.pump();
      expect(checker.accessibilityCalls.length, before + 1);
      // Later is disabled while verifying.
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Set up click control later'),
            )
            .onPressed,
        isNull,
      );
      checker.accessibilityCalls.last.complete(true);
      await t.pumpAndSettle();
      // The grant shows as Continue; it never advances or persists alone.
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Accessibility'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding.step.accessibility'), isNull);
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
      await t.tap(find.text('Check again'));
      await t.pump();
      await t.tap(find.text('Check again'), warnIfMissed: false);
      await t.pump();
      expect(checker.accessibilityCalls.length, before + 1);
      checker.accessibilityCalls.last.complete(false);
      await t.pumpAndSettle();
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Check again'),
            )
            .onPressed,
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
      await t.tap(find.text('Check again'));
      await t.pumpAndSettle();
      expect(find.textContaining('Could not check'), findsOneWidget);
      expect(find.text('Accessibility'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding.step.accessibility'), isNull);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Check again'),
            )
            .onPressed,
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
      expect(find.text('Check again'), findsNothing);
      expect(find.textContaining('Not granted'), findsNothing);
      expect(find.textContaining('pair the phone'), findsOneWidget);
      expect(find.text('Continue to summary'), findsOneWidget);
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
