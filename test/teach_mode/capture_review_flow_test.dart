import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/capture_monitor.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/teach_mode/capture_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ac1 review is read-only and abort discards preview', () async {
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

      final preview = session.review();
      expect(preview.steps, hasLength(1));
      expect(preview.steps.single.target, 'save');
      expect(preview.canAutoExecute, isFalse);
      expect(session.stepCount, 1);
      expect(session.indicator, CaptureIndicator.active);
      expect(() => preview.steps.clear(), throwsUnsupportedError);

      session.cancel();
      expect(session.review().steps, isEmpty);
      expect(session.stepCount, 0);
      expect(session.indicator, CaptureIndicator.off);
      expect(preview.steps, hasLength(1));
    } finally {
      session.dispose();
    }
  });
}
