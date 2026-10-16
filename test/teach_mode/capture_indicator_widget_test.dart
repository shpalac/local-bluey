import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/capture_monitor.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/teach_mode/capture_session.dart';
import 'package:local_bluey/ui/teach_capture_panel.dart';
import 'package:local_bluey/ui/watch_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Strings.uiLanguage = UiLanguage.english;
  });
  tearDown(() {
    Strings.uiLanguage = UiLanguage.system;
  });

  testWidgets(
    'teach mode indicator shows active paused and off on revoke cancel restart',
    (tester) async {
      final allowlist = <String>['editor'];
      final watch = ScreenWatch.forTesting(
        localOnly: () async => true,
        allowlist: () async => allowlist,
        denylist: () async => <String>[],
      );
      final session = TeachCaptureSession(watch: watch);
      addTearDown(() {
        session.dispose();
        watch.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              WatchBanner(watch: watch, teachSession: session, child: child!),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TeachCapturePanel(session: session, watch: watch),
            ),
          ),
        ),
      );
      expect(find.text('Teach Mode: off'), findsOneWidget);
      expect(find.text('Teach Mode active'), findsNothing);
      expect(watch.isActive, isFalse);

      await tester.tap(find.text('Start Teach Mode'));
      await tester.pumpAndSettle();
      expect(find.text('Start Teach Mode?'), findsOneWidget);
      expect(watch.isActive, isFalse);
      await tester.tap(find.text('I agree — start'));
      await tester.pumpAndSettle();

      expect(session.indicator, CaptureIndicator.active);
      expect(find.text('Teach Mode: active'), findsOneWidget);
      expect(find.text('Teach Mode active'), findsOneWidget);
      expect(
        await session.observe(
          frontApp: 'editor',
          capture: () async => {'action': 'click', 'target': 'save'},
        ),
        isTrue,
      );
      expect(session.stepCount, 1);

      // Unknown/sensitive foreground must discard before the UI can
      // present a misleading active indicator or resume automatically.
      var invoked = false;
      expect(
        await session.observe(
          frontApp: '1Password',
          capture: () async {
            invoked = true;
            return {'action': 'click', 'target': 'private'};
          },
        ),
        isFalse,
      );
      await tester.pump();
      expect(invoked, isFalse);
      expect(session.stepCount, 0);
      expect(session.indicator, CaptureIndicator.paused);
      expect(find.text('Teach Mode: paused'), findsOneWidget);
      expect(find.text('Teach Mode paused'), findsOneWidget);
      expect(find.text('Teach Mode active'), findsNothing);

      await tester.tap(find.text('Resume Teach Mode'));
      await tester.pump();
      expect(session.indicator, CaptureIndicator.active);

      // Policy revocation ends the session; the old UI cannot imply a
      // recording continues after the allowlist has been removed.
      allowlist.clear();
      expect(
        await session.observe(
          frontApp: 'editor',
          capture: () async => {'action': 'click', 'target': 'late'},
        ),
        isFalse,
      );
      await tester.pump();
      expect(session.indicator, CaptureIndicator.off);
      expect(watch.isActive, isFalse);
      expect(session.stepCount, 0);
      expect(find.text('Teach Mode: off'), findsOneWidget);
      expect(find.text('Teach Mode active'), findsNothing);

      allowlist.add('editor');
      await tester.tap(find.text('Start Teach Mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I agree — start'));
      await tester.pumpAndSettle();
      expect(session.indicator, CaptureIndicator.active);
      await tester.tap(find.text('Cancel Teach Mode'));
      await tester.pump();
      expect(session.indicator, CaptureIndicator.off);
      expect(watch.isActive, isFalse);
      expect(session.review().steps, isEmpty);
      expect(find.text('Teach Mode paused'), findsNothing);

      final restartedWatch = ScreenWatch.forTesting(
        localOnly: () async => true,
        allowlist: () async => ['editor'],
        denylist: () async => <String>[],
      );
      final restarted = TeachCaptureSession(watch: restartedWatch);
      expect(restarted.indicator, CaptureIndicator.off);
      expect(restarted.stepCount, 0);
      expect(restarted.review().steps, isEmpty);
      restarted.dispose();
      restartedWatch.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ordinary watching never becomes Teach Mode and cannot be cancelled by teaching',
    (tester) async {
      final watch = ScreenWatch.forTesting(
        localOnly: () async => true,
        allowlist: () async => ['editor'],
        denylist: () async => <String>[],
      );
      final session = TeachCaptureSession(watch: watch);
      addTearDown(() {
        session.dispose();
        watch.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              WatchBanner(watch: watch, teachSession: session, child: child!),
          home: Scaffold(
            body: TeachCapturePanel(session: session, watch: watch),
          ),
        ),
      );

      expect(await watch.start(consentConfirmed: true), isNull);
      await tester.pump();
      expect(watch.isActive, isTrue);
      expect(session.indicator, CaptureIndicator.off);
      expect(find.text('Teach Mode: off'), findsOneWidget);
      expect(find.text('Teach Mode active'), findsNothing);
      expect(find.textContaining('Watching'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      final start = tester.widget<FilledButton>(
        find.byKey(const ValueKey('teach-start')),
      );
      expect(start.onPressed, isNull);

      // Teaching teardown must not stop a distinct ordinary watch session.
      session.cancel();
      expect(watch.isActive, isTrue);
      watch.stop();
      await tester.pump();
      expect(find.text('Stop'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
