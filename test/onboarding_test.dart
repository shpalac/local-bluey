import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local_bluey/services/first_success.dart';
import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/services/strings.dart';
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

Future<(ServiceReadiness, ServiceReadiness)> _fakeReady() async =>
    (ServiceReadiness.ready, ServiceReadiness.ready);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OnboardingScreen stepper', () {
    testWidgets('opens on the first permission step', (t) async {
      await t.pumpWidget(
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: _StubChecker({}),
            onDone: () {},
          ),
        ),
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
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: _StubChecker({}),
            onDone: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Microphone'), findsOneWidget);
      expect(find.textContaining('later'), findsOneWidget); // Finish only
      expect(find.text('Set up Microphone'), findsOneWidget); // heading
    });

    testWidgets('verify advances only after the grant exists', (t) async {
      final checker = _StubChecker({});
      await t.pumpWidget(
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: checker,
            onDone: () {},
          ),
        ),
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
      expect(find.text('Granted'), findsOneWidget);
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
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: _StubChecker({}),
            onDone: () {},
          ),
        ),
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
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: checker,
            onDone: () {},
          ),
        ),
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
            readiness: _fakeReady,
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
      expect(find.textContaining('cannot hear you'), findsWidgets);
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
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: _StubChecker({}),
            onDone: () {},
          ),
        ),
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
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: checker,
            onDone: () {},
          ),
        ),
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
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: checker,
            onDone: () {},
          ),
        ),
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
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: checker,
            onDone: () {},
          ),
        ),
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
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: _ThrowingChecker(),
            onDone: () {},
          ),
        ),
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
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: _ThrowingChecker(),
            onDone: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      // Step 2 is Screen Recording, which the throwing checker grants.
      expect(find.text('Screen Recording'), findsOneWidget);
      expect(find.text('Granted'), findsOneWidget);
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
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: _StubChecker({}),
            onDone: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Local Network'), findsOneWidget);
      expect(find.text('Check again'), findsNothing);
      expect(find.textContaining('Not granted'), findsNothing);
      expect(find.textContaining('pair the phone'), findsOneWidget);
      expect(find.text('Continue to summary'), findsOneWidget);
    });
  });

  group('First-success summary (#226)', () {
    Future<void> openSummary(WidgetTester t, OnboardingScreen s) async {
      await t.pumpWidget(_app(s));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Finish setup later'));
      await t.tap(find.text('Finish setup later'));
      await t.pumpAndSettle();
    }

    testWidgets('screen deferred: first request does not need the screen', (
      t,
    ) async {
      FirstSuccessPlan? plan;
      await openSummary(
        t,
        OnboardingScreen(
          readiness: _fakeReady,
          checker: _StubChecker({'microphone': true}),
          onDone: () {},
          onPlan: (p) => plan = p,
        ),
      );
      expect(find.textContaining('Try this first'), findsOneWidget);
      expect(find.textContaining('what can you do'), findsOneWidget);
      expect(find.textContaining("on my screen"), findsNothing);
      expect(find.byKey(const Key('no-pointing')), findsOneWidget);
      await t.tap(find.text('Start Bluey'));
      await t.pumpAndSettle();
      expect(plan!.pointingAvailable, isFalse);
      expect(plan!.screenQuestionAvailable, isFalse);
    });

    testWidgets('everything granted: screen question, pointing offered', (
      t,
    ) async {
      FirstSuccessPlan? plan;
      await openSummary(
        t,
        OnboardingScreen(
          readiness: _fakeReady,
          checker: _StubChecker({
            'accessibility': true,
            'screen_recording': true,
            'microphone': true,
          }),
          onDone: () {},
          onPlan: (p) => plan = p,
        ),
      );
      expect(find.textContaining("on my screen"), findsOneWidget);
      expect(find.byKey(const Key('no-pointing')), findsNothing);
      await t.tap(find.text('Start Bluey'));
      await t.pumpAndSettle();
      expect(plan!.pointingAvailable, isTrue);
    });

    testWidgets('unreachable brain gives a fix, not a ready claim', (t) async {
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      var opened = false;
      await openSummary(
        t,
        OnboardingScreen(
          readiness: () async =>
              (ServiceReadiness.unreachable, ServiceReadiness.ready),
          checker: _StubChecker({'microphone': true}),
          onDone: () {},
          onOpenSettings: () => opened = true,
        ),
      );
      expect(find.textContaining('Try this first'), findsNothing);
      expect(find.byKey(const Key('issue-brain')), findsOneWidget);
      await t.ensureVisible(find.text('Open Settings'));
      await t.tap(find.text('Open Settings'));
      await t.pump();
      expect(opened, isTrue);
    });

    testWidgets('start waits for the readiness check', (t) async {
      final gate = Completer<(ServiceReadiness, ServiceReadiness)>();
      await t.pumpWidget(
        _app(
          OnboardingScreen(
            readiness: () => gate.future,
            checker: _StubChecker({'microphone': true}),
            onDone: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Finish setup later'));
      await t.tap(find.text('Finish setup later'));
      await t.pumpAndSettle();
      expect(find.text('Checking...'), findsOneWidget);
      expect(find.text('Start Bluey'), findsNothing);
      gate.complete((ServiceReadiness.ready, ServiceReadiness.ready));
      await t.pumpAndSettle();
      expect(find.text('Start Bluey'), findsOneWidget);
    });
  });

  group('Onboarding localization and semantics (#227)', () {
    final hebrew = RegExp(r'[\u0590-\u05FF]');
    final english = RegExp(r'[A-Za-z]{4,}');

    tearDown(() => Strings.uiLanguage = UiLanguage.english);

    test('every permission has Hebrew copy', () {
      for (final p in onboardingPermissions) {
        expect(hebrew.hasMatch(p.titleHe), isTrue, reason: p.id);
        expect(hebrew.hasMatch(p.whyHe), isTrue, reason: p.id);
      }
    });

    testWidgets('Hebrew UI shows Hebrew text on every step', (t) async {
      Strings.uiLanguage = UiLanguage.hebrew;
      t.view.physicalSize = const Size(800, 1200);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: OnboardingScreen(
              readiness: _fakeReady,
              checker: _StubChecker({}),
              onDone: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      for (var i = 0; i < onboardingPermissions.length; i++) {
        final p = onboardingPermissions[i];
        await t.tap(find.byKey(Key('step-${p.id}')));
        await t.pumpAndSettle();
        expect(find.text(p.titleHe), findsWidgets, reason: p.id);
        expect(find.text(p.whyHe), findsOneWidget, reason: p.id);
        // The status line is Hebrew, not English.
        final status = t.widget<Text>(
          find.byKey(const Key('onboarding-state')),
        );
        expect(hebrew.hasMatch(status.data!), isTrue, reason: p.id);
        // Product names (macOS, iPhone) stay Latin inside Hebrew text.
        final prose = status.data!.replaceAll(RegExp('macOS|iPhone'), '');
        expect(english.hasMatch(prose), isFalse, reason: p.id);
      }
    });

    testWidgets('status is announced as text, not colour or icon alone', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: _StubChecker({}),
            onDone: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Not enabled'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Accessibility: Not enabled'),
        findsOneWidget,
      );
      final node = t.getSemantics(
        find.bySemanticsLabel('Accessibility: Not enabled'),
      );
      expect(node.flagsCollection.isLiveRegion, isTrue);
      // The heading is a named header and the primary action is enabled.
      expect(find.bySemanticsLabel('Set up Accessibility'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Open Settings'),
            )
            .onPressed,
        isNotNull,
      );
      handle.dispose();
    });

    testWidgets('unable to check is a visible, named status', (t) async {
      await t.pumpWidget(
        _app(
          OnboardingScreen(
            readiness: _fakeReady,
            checker: _ThrowingChecker(),
            onDone: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Unable to check'), findsWidgets);
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
