import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/capture_monitor.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/teach_mode/capture_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ScreenWatch newWatch({
    Clock? clock,
    Future<bool> Function()? localOnly,
    Future<List<String>> Function()? allowlist,
  }) => ScreenWatch.forTesting(
    clock: clock,
    localOnly: localOnly ?? () async => true,
    allowlist: allowlist ?? () async => ['editor'],
    denylist: () async => <String>[],
  );

  Future<bool> click(TeachCaptureSession session, {String app = 'editor'}) =>
      session.observe(
        frontApp: app,
        capture: () async => {'action': 'click', 'target': 'save'},
      );

  test('ac2 denied or unknown app pauses until user resumes', () async {
    final session = TeachCaptureSession(watch: newWatch());
    try {
      expect(await session.start(consentConfirmed: true), isNull);
      expect(await click(session), isTrue);
      expect(session.stepCount, 1);
      expect(await click(session, app: '1Password'), isFalse);
      expect(session.indicator, CaptureIndicator.paused);
      expect(session.stepCount, 0);

      var invoked = false;
      expect(
        await session.observe(
          frontApp: 'editor',
          capture: () async {
            invoked = true;
            return {'action': 'click', 'target': 'save'};
          },
        ),
        isFalse,
      );
      expect(invoked, isFalse);
      expect(session.resume(), isTrue);
      expect(await click(session), isTrue);
      expect(await click(session, app: 'unknown-app'), isFalse);
      expect(session.indicator, CaptureIndicator.paused);
      expect(session.review().steps, isEmpty);
    } finally {
      session.dispose();
    }
  });

  test('ac2 timeout expires and destroys uncommitted observations', () async {
    var now = DateTime.utc(2026, 10, 16);
    final session = TeachCaptureSession(
      watch: newWatch(clock: Clock(() => now)),
    );
    try {
      expect(
        await session.start(
          consentConfirmed: true,
          duration: const Duration(seconds: 2),
        ),
        isNull,
      );
      expect(await click(session), isTrue);
      now = now.add(const Duration(seconds: 3));
      var invoked = false;
      expect(
        await session.observe(
          frontApp: 'editor',
          capture: () async {
            invoked = true;
            return {'action': 'click', 'target': 'late'};
          },
        ),
        isFalse,
      );
      expect(invoked, isFalse);
      expect(session.indicator, CaptureIndicator.off);
      expect(session.stepCount, 0);
      expect(session.resume(), isFalse);
    } finally {
      session.dispose();
    }
  });

  test('ac2 offline and permission revocation terminate capture', () async {
    var localOnly = true;
    final allowedApps = <String>['editor'];
    final session = TeachCaptureSession(
      watch: newWatch(
        localOnly: () async => localOnly,
        allowlist: () async => allowedApps,
      ),
    );
    try {
      expect(await session.start(consentConfirmed: true), isNull);
      expect(await click(session), isTrue);
      localOnly = false;
      expect(await click(session), isFalse);
      expect(session.indicator, CaptureIndicator.off);
      expect(session.stepCount, 0);

      localOnly = true;
      expect(await session.start(consentConfirmed: true), isNull);
      expect(await click(session), isTrue);
      allowedApps.clear();
      expect(await click(session), isFalse);
      expect(session.indicator, CaptureIndicator.off);
      expect(session.stepCount, 0);
    } finally {
      session.dispose();
    }
  });

  test('ac2 concurrent start cancelled mid-check never resurrects', () async {
    final permission = Completer<bool>();
    final session = TeachCaptureSession(
      watch: newWatch(localOnly: () => permission.future),
    );
    try {
      final pendingStart = session.start(consentConfirmed: true);
      expect(await session.start(consentConfirmed: true), isNotNull);
      session.cancel();
      permission.complete(true);
      expect(await pendingStart, isNotNull);
      expect(session.indicator, CaptureIndicator.off);
      expect(session.stepCount, 0);
      expect(await session.start(consentConfirmed: true), isNull);
    } finally {
      session.dispose();
    }
  });

  test('ac2 capture errors pause and require explicit resume', () async {
    final session = TeachCaptureSession(watch: newWatch());
    try {
      expect(await session.start(consentConfirmed: true), isNull);
      expect(
        await session.observe(
          frontApp: 'editor',
          capture: () async => throw StateError('untrusted payload'),
        ),
        isFalse,
      );
      expect(session.indicator, CaptureIndicator.paused);
      expect(session.stepCount, 0);
      expect(session.resume(), isTrue);
      expect(await click(session), isTrue);
    } finally {
      session.dispose();
    }
  });

  test('ac2 cancellation fences in-flight result and restart is off', () async {
    final entered = Completer<void>();
    final captured = Completer<Map<String, Object?>>();
    final session = TeachCaptureSession(watch: newWatch());
    try {
      expect(await session.start(consentConfirmed: true), isNull);
      final pending = session.observe(
        frontApp: 'editor',
        capture: () {
          entered.complete();
          return captured.future;
        },
      );
      await entered.future;
      session.cancel();
      captured.complete({'action': 'click', 'target': 'stale'});
      expect(await pending, isFalse);
      expect(session.stepCount, 0);
      expect(session.indicator, CaptureIndicator.off);

      final fresh = TeachCaptureSession(watch: newWatch());
      try {
        expect(fresh.indicator, CaptureIndicator.off);
        expect(fresh.review().steps, isEmpty);
        expect(await click(fresh), isFalse);
      } finally {
        fresh.dispose();
      }
    } finally {
      session.dispose();
    }
  });
}
