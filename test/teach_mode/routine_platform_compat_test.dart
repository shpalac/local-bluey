import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/capture_monitor.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/teach_mode/capture_session.dart';
import 'package:local_bluey/workflows/legacy_routine_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const original = Routine(
    name: 'Reminder',
    trigger: 'remind me',
    instructions: 'notify:Take a break',
  );

  Future<TeachCaptureSession> captureTwoSteps(ScreenWatch watch) async {
    final session = TeachCaptureSession(watch: watch);
    expect(await session.start(consentConfirmed: true), isNull);
    expect(
      await session.observe(
        frontApp: 'editor',
        capture: () async => {'action': 'click', 'target': 'save'},
      ),
      isTrue,
    );
    expect(
      await session.observe(
        frontApp: 'editor',
        capture: () async => {'action': 'type', 'target': 'notes'},
      ),
      isTrue,
    );
    expect(session.stepCount, 2);
    expect(session.review().canAutoExecute, isFalse);
    return session;
  }

  test('ac4 legacy routines stay untouched during and after capture', () async {
    final watch = ScreenWatch.forTesting(
      localOnly: () async => true,
      allowlist: () async => ['editor'],
      denylist: () async => <String>[],
    );
    final before = original.toJson();
    final expected = LegacyRoutineAdapter.toWorkflow(original).encode();

    final session = await captureTwoSteps(watch);
    try {
      // The adapter path behaves identically mid-capture and produces the
      // same manual workflow it did before Teach Mode existed.
      final workflow = LegacyRoutineAdapter.toWorkflow(original);
      expect(workflow.encode(), expected);
      expect(workflow.trigger, 'manual');
      expect(workflow.steps.single.type, 'notify');
      expect(original.toJson(), before);

      // The finished teach draft never becomes a workflow: it ends capture
      // and stays a review artifact with zero execution rights.
      final draft = session.finish();
      expect(draft.steps, hasLength(2));
      expect(draft.canAutoExecute, isFalse);

      // And the adapter again, after capture, is byte-for-byte unchanged.
      expect(LegacyRoutineAdapter.toWorkflow(original).encode(), expected);
      expect(original.toJson(), before);

      // Free-form legacy instructions still fail closed next to capture.
      expect(
        () => LegacyRoutineAdapter.toWorkflow(
          const Routine(
            name: 'unsafe',
            trigger: 'go',
            instructions: 'run shell command',
          ),
        ),
        throwsA(isA<LegacyRoutineConversionException>()),
      );
    } finally {
      session.dispose();
      expect(original.toJson(), before);
    }
  });

  test(
    'ac4 capture gates behave identically across platform flavors',
    () async {
      // The same allowlist/denylist/local-only gates each supported host lane
      // already relies on must produce identical Teach Mode behavior.
      const flavors = {
        'macOS': 'com.apple.TextEdit',
        'iOS': 'EditMode',
        'Android': 'editor',
      };
      for (final entry in flavors.entries) {
        final session = TeachCaptureSession(
          watch: ScreenWatch.forTesting(
            localOnly: () async => true,
            allowlist: () async => [entry.value],
            denylist: () async => <String>[],
          ),
        );
        expect(await session.start(consentConfirmed: true), isNull);
        expect(session.indicator, CaptureIndicator.active);

        // Non-allowlisted app stays refused on every flavor.
        expect(
          await session.observe(
            frontApp: 'not-on-list',
            capture: () async => {'action': 'click', 'target': 'save'},
          ),
          isFalse,
        );
        expect(session.stepCount, 0);

        // Allowlisted app captures the same way, pause/resume gates it, and
        // restart is clean on every flavor.
        expect(
          await session.observe(
            frontApp: entry.value,
            capture: () async => {'action': 'click', 'target': 'save'},
          ),
          isTrue,
        );
        expect(session.stepCount, 1);
        // Pausing sheds captured steps: a paused capture can never resume into
        // its old draft; only new, clean, post-resume steps rebuild the
        // draft on every flavor.
        expect(session.pause(), isTrue);
        expect(session.indicator, CaptureIndicator.paused);
        expect(session.stepCount, 0);
        expect(session.resume(), isTrue);
        expect(session.indicator, CaptureIndicator.active);
        expect(
          await session.observe(
            frontApp: entry.value,
            capture: () async => {'action': 'type', 'target': 'notes'},
          ),
          isTrue,
        );
        expect(session.stepCount, 1);

        session.cancel();
        expect(session.indicator, CaptureIndicator.off);
        expect(session.review().steps, isEmpty);
        expect(await session.start(consentConfirmed: true), isNull);
        session.dispose();
      }
    },
  );
}
