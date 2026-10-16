import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/capture_monitor.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/teach_mode/capture_session.dart';
import 'package:local_bluey/teach_mode/draft_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ScreenWatch newWatch() => ScreenWatch.forTesting(
    localOnly: () async => true,
    allowlist: () async => ['editor'],
    denylist: () async => <String>[],
  );

  Future<bool> observeGood(TeachCaptureSession session) => session.observe(
    frontApp: 'editor',
    capture: () async => {'action': 'click', 'target': 'save'},
  );

  test(
    'ac2 validation is deterministic and every refusal is explicit',
    () async {
      final session = TeachCaptureSession(watch: newWatch());

      // Start refusals surface distinct explicit reasons, never a silent go.
      expect(
        await session.start(consentConfirmed: false),
        'Explicit user consent is required.',
      );
      expect(
        await session.start(
          consentConfirmed: true,
          duration: const Duration(minutes: 11),
        ),
        'Duration must be positive and at most ten minutes.',
      );
      expect(
        await session.start(consentConfirmed: true, duration: Duration.zero),
        'Duration must be positive and at most ten minutes.',
      );
      expect(session.indicator, CaptureIndicator.off);

      expect(await session.start(consentConfirmed: true), isNull);
      expect(session.indicator, CaptureIndicator.active);
      expect(
        await session.start(consentConfirmed: true),
        'A session is already active or starting.',
      );

      // Observation outside an active session is refused to the caller, not
      // silently buffered until the next session.
      session.cancel();
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

      // A capture that races a stop is dropped by the epoch guard: the result
      // can never join a draft the user already aborted.
      expect(await session.start(consentConfirmed: true), isNull);
      final lateCapture = session.observe(
        frontApp: 'editor',
        capture: () async {
          session.cancel();
          return {'action': 'click', 'target': 'later'};
        },
      );
      expect(await lateCapture, isFalse);
      expect(session.stepCount, 0);

      // Determinism: identical inputs always build identical previews.
      const observations = [
        {'action': 'click', 'target': 'save'},
        {'action': 'type', 'target': 'notes'},
      ];
      const builder = TeachDraftBuilder();
      final first = builder.preview(observations);
      final second = builder.preview(observations);
      expect(first.warnings, second.warnings);
      expect(
        first.steps
            .map(
              (s) =>
                  '${s.ordinal}:${s.kind}:${s.target}'
                  ':${s.requiresReview}:${s.variablePlaceholder}',
            )
            .join('|'),
        second.steps
            .map(
              (s) =>
                  '${s.ordinal}:${s.kind}:${s.target}'
                  ':${s.requiresReview}:${s.variablePlaceholder}',
            )
            .join('|'),
      );
      expect(first.canAutoExecute, isFalse);
      expect(second.canAutoExecute, isFalse);

      // Restart after stop starts clean, again with an explicit indicator.
      expect(session.indicator, CaptureIndicator.off);
      expect(await session.start(consentConfirmed: true), isNull);
      expect(await observeGood(session), isTrue);
      expect(session.stepCount, 1);
      final restarted = TeachCaptureSession(watch: newWatch());
      expect(restarted.indicator, CaptureIndicator.off);
      expect(restarted.stepCount, 0);
      restarted.dispose();
      session.dispose();
    },
  );
}
