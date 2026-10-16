import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/capture_monitor.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/teach_mode/capture_session.dart';

/// Fixed, manually-advancable clock for timeout fixtures.
class _MutableClock extends Clock {
  _MutableClock(this.hour);
  DateTime hour;
  @override
  DateTime now() => hour;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ac2 timeout expiry refuses observation and stops capture', () async {
    final clock = _MutableClock(DateTime(2026, 10, 15, 12));
    final session = TeachCaptureSession(
      watch: ScreenWatch.forTesting(
        clock: clock,
        localOnly: () async => true,
        allowlist: () async => ['editor'],
        denylist: () async => <String>[],
      ),
    );
    expect(await session.start(consentConfirmed: true), isNull);
    expect(
      await session.observe(
        frontApp: 'editor',
        capture: () async => {'action': 'click', 'target': 'save'},
      ),
      isTrue,
    );
    expect(session.indicator, CaptureIndicator.active);

    // Moving past the committed session length: the next observation is
    // refused, the session is stopped and nothing resumes afterwards.
    clock.hour = clock.hour.add(const Duration(minutes: 10, seconds: 1));
    var invoked = false;
    expect(
      await session.observe(
        frontApp: 'editor',
        capture: () async {
          invoked = true;
          return {'action': 'click', 'target': 'later'};
        },
      ),
      isFalse,
    );
    expect(invoked, isFalse);
    expect(session.indicator, CaptureIndicator.off);
    expect(session.stepCount, 0);
    expect(session.review().steps, isEmpty);

    // Explicit re-consent restarts cleanly after the timeout.
    expect(
      await session.start(consentConfirmed: true),
      isNull,
      reason: 'a stopped session may start again with explicit consent',
    );
    expect(session.indicator, CaptureIndicator.active);
    session.dispose();
  });

  test('ac2 offline refusal is explicit and stays off', () async {
    var localOnly = false;
    final session = TeachCaptureSession(
      watch: ScreenWatch.forTesting(
        localOnly: () async => localOnly,
        allowlist: () async => ['editor'],
        denylist: () async => <String>[],
      ),
    );
    // Offline start is refused with one explicit reason, not silently.
    expect(await session.start(consentConfirmed: true), contains('local-only'));
    expect(session.indicator, CaptureIndicator.off);
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

    // Local-only restored mid-instance enables the next start.
    localOnly = true;
    expect(await session.start(consentConfirmed: true), isNull);
    expect(session.indicator, CaptureIndicator.active);
    session.dispose();
  });

  test(
    'ac2 mid-session policy tightening denies the next observation',
    () async {
      var allowlist = ['editor'];
      final session = TeachCaptureSession(
        watch: ScreenWatch.forTesting(
          localOnly: () async => true,
          allowlist: () async => allowlist,
          denylist: () async => <String>[],
        ),
      );
      expect(await session.start(consentConfirmed: true), isNull);
      expect(
        await session.observe(
          frontApp: 'editor',
          capture: () async => {'action': 'click', 'target': 'safe'},
        ),
        isTrue,
      );
      expect(session.stepCount, 1);

      // The user removes the app from the allowlist: the session stops and
      // the very next observation is refused, never silently captured.
      allowlist = ['terminal'];
      expect(
        await session.observe(
          frontApp: 'editor',
          capture: () async => {'action': 'click', 'target': 'after'},
        ),
        isFalse,
      );
      expect(session.indicator, CaptureIndicator.off);
      session.dispose();
    },
  );

  test('ac2 malformed capture results are refused without retention', () async {
    final session = TeachCaptureSession(
      watch: ScreenWatch.forTesting(
        localOnly: () async => true,
        allowlist: () async => ['editor'],
        denylist: () async => <String>[],
      ),
    );
    expect(await session.start(consentConfirmed: true), isNull);
    const malformed = [
      {'action': 'click', 'target': 42},
      {'action': 'swipe', 'target': 'valid'},
      {'action': 'click', 'target': 'save', 'payload': 'extra'},
      {
        'action': 'type',
        'target': 'notes',
        'value': 'typed text is payload, not target',
      },
    ];
    for (final capture in malformed) {
      expect(
        await session.observe(frontApp: 'editor', capture: () async => capture),
        isFalse,
      );
    }
    expect(session.stepCount, 0);
    // A clean capture right after still works deterministically.
    expect(
      await session.observe(
        frontApp: 'editor',
        capture: () async => {'action': 'click', 'target': 'save'},
      ),
      isTrue,
    );
    expect(session.stepCount, 1);
    session.dispose();
  });

  test('ac2 restart yields a clean session state', () async {
    final session = TeachCaptureSession(
      watch: ScreenWatch.forTesting(
        localOnly: () async => true,
        allowlist: () async => ['editor'],
        denylist: () async => <String>[],
      ),
    );
    try {
      expect(await session.start(consentConfirmed: true), isNull);
      expect(
        await session.observe(
          frontApp: 'editor',
          capture: () async => {'action': 'click', 'target': 'save'},
        ),
        isTrue,
      );
      session.finish();
      expect(session.stepCount, 0);
      expect(session.indicator, CaptureIndicator.off);
      expect(session.review().steps, isEmpty);

      // A brand-new instance has no memory of the restart flow's capture.
      final revived = TeachCaptureSession(
        watch: ScreenWatch.forTesting(
          localOnly: () async => true,
          allowlist: () async => ['editor'],
          denylist: () async => <String>[],
        ),
      );
      expect(revived.indicator, CaptureIndicator.off);
      expect(revived.stepCount, 0);
      revived.dispose();
    } finally {
      session.dispose();
    }
  });
}
