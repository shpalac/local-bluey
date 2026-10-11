import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local_bluey/services/first_success.dart';
import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/ui/onboarding_screen.dart';

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

const _notice = 'Could not save setup. Tap Start Bluey to try again.';

void main() {
  late List<String> events;
  late int writes;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    events = [];
    writes = 0;
  });
  tearDown(() => OnboardingScreen.debugWriteDone = null);

  Future<void> openSummary(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          readiness: _ready,
          checker: _Checker(),
          onDone: () => events.add('done'),
          onPlan: (_) => events.add('plan'),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Finish setup later'));
    await t.tap(find.text('Finish setup later'));
    await t.pumpAndSettle();
  }

  testWidgets('repeat presses join one write; plan and done follow it', (
    t,
  ) async {
    await openSummary(t);
    final hold = Completer<bool>();
    OnboardingScreen.debugWriteDone = () {
      writes++;
      events.add('write');
      return hold.future;
    };
    await t.tap(find.text('Start Bluey'));
    await t.pump();
    await t.tap(find.text('Start Bluey'), warnIfMissed: false);
    await t.pump();
    expect(writes, 1);
    expect(events, ['write']);
    hold.complete(true);
    await t.pumpAndSettle();
    expect(events, ['write', 'plan', 'done']);
  });

  for (final mode in ['false', 'throw']) {
    testWidgets('$mode write: one safe error, no handoff, retry works', (
      t,
    ) async {
      await openSummary(t);
      OnboardingScreen.debugWriteDone = () async {
        writes++;
        if (mode == 'throw') throw StateError('/private/path token');
        return false;
      };
      await t.tap(find.text('Start Bluey'));
      await t.pumpAndSettle();
      expect(find.text(_notice), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
      expect(events, isEmpty);
      OnboardingScreen.debugWriteDone = () async {
        writes++;
        return true;
      };
      await t.tap(find.text('Start Bluey'));
      await t.pumpAndSettle();
      expect(writes, 2);
      expect(events, ['plan', 'done']);
    });
  }

  testWidgets('held write then disposal has no late callback', (t) async {
    await openSummary(t);
    final hold = Completer<bool>();
    OnboardingScreen.debugWriteDone = () => hold.future;
    await t.tap(find.text('Start Bluey'));
    await t.pump();
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    hold.complete(true);
    await t.pump();
    await t.pump();
    expect(events, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('real preferences write persists done before handoff', (t) async {
    await openSummary(t);
    await t.runAsync(() async {
      await t.tap(find.text('Start Bluey'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pump();
    expect(events, ['plan', 'done']);
    expect(await OnboardingScreen.isDone(), isTrue);
  });
}
