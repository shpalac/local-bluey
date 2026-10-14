import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/capture_monitor.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/teach_mode/capture_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ScreenWatch newWatch() => ScreenWatch.forTesting(
    localOnly: () async => true,
    allowlist: () async => ['editor'],
    denylist: () async => <String>[],
  );

  test('ac1 cancel drops captured steps and restart stays off', () async {
    final session = TeachCaptureSession(watch: newWatch());
    expect(await session.start(consentConfirmed: true), isNull);
    expect(
      await session.observe(
        frontApp: 'editor',
        capture: () async => {'action': 'click', 'target': 'save'},
      ),
      isTrue,
    );
    expect(session.stepCount, 1);
    session.cancel();
    expect(session.stepCount, 0);
    expect(session.indicator, CaptureIndicator.off);
    expect(session.finish().steps, isEmpty);
    final restarted = TeachCaptureSession(watch: newWatch());
    expect(restarted.indicator, CaptureIndicator.off);
    expect(restarted.stepCount, 0);
    restarted.dispose();
    session.dispose();
  });

  test('ac2 rejected consent duration and denied app do not capture', () async {
    final session = TeachCaptureSession(watch: newWatch());
    expect(await session.start(consentConfirmed: false), isNotNull);
    expect(
      await session.start(
        consentConfirmed: true,
        duration: const Duration(minutes: 11),
      ),
      isNotNull,
    );
    expect(session.indicator, CaptureIndicator.off);
    expect(await session.start(consentConfirmed: true), isNull);
    var invoked = false;
    expect(
      await session.observe(
        frontApp: '1Password',
        capture: () async {
          invoked = true;
          return {'action': 'click', 'target': 'secret'};
        },
      ),
      isFalse,
    );
    expect(invoked, isFalse);
    expect(session.stepCount, 0);
    session.dispose();
  });

  test('ac3 secret-bearing input discarded and draft cannot execute', () async {
    final session = TeachCaptureSession(watch: newWatch());
    expect(await session.start(consentConfirmed: true), isNull);
    expect(
      await session.observe(
        frontApp: 'editor',
        capture: () async => {
          'action': 'type',
          'target': 'password',
          'text': 'secret',
        },
      ),
      isFalse,
    );
    expect(
      await session.observe(
        frontApp: 'editor',
        capture: () async => {'action': 'click', 'target': 'save'},
      ),
      isTrue,
    );
    final draft = session.finish();
    expect(draft.steps, hasLength(1));
    expect(draft.steps.single.target, 'save');
    expect(draft.canAutoExecute, isFalse);
    expect(session.stepCount, 0);
    session.dispose();
  });
}
