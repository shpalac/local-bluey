import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/first_success.dart';

FirstSuccessInputs _in({
  bool ax = true,
  bool screen = true,
  bool mic = true,
  ServiceReadiness brain = ServiceReadiness.ready,
  ServiceReadiness stt = ServiceReadiness.ready,
}) => FirstSuccessInputs(
  accessibility: ax,
  screenRecording: screen,
  microphone: mic,
  brain: brain,
  stt: stt,
);

void main() {
  group('FirstSuccessPlan', () {
    test('screen-ready: screen question and pointing offered', () {
      final p = FirstSuccessPlan.from(_in());
      expect(p.voiceReady, isTrue);
      expect(p.suggestedRequest, "what's on my screen?");
      expect(p.screenQuestionAvailable, isTrue);
      expect(p.pointingAvailable, isTrue);
    });

    test('screen deferred: voice-only question, no pointing', () {
      final p = FirstSuccessPlan.from(_in(screen: false));
      expect(p.voiceReady, isTrue);
      expect(p.suggestedRequest, isNot(contains('screen')));
      expect(p.screenQuestionAvailable, isFalse);
      expect(p.pointingAvailable, isFalse);
    });

    test('accessibility deferred: screen question yes, pointing no', () {
      final p = FirstSuccessPlan.from(_in(ax: false));
      expect(p.screenQuestionAvailable, isTrue);
      expect(p.pointingAvailable, isFalse);
    });

    test('denied mic: no first request, actionable issue', () {
      final p = FirstSuccessPlan.from(_in(mic: false));
      expect(p.voiceReady, isFalse);
      expect(p.suggestedRequest, isNull);
      expect(p.issues.single.id, 'microphone');
      expect(p.pointingAvailable, isFalse);
    });

    test('unreachable brain and unconfigured stt both reported', () {
      final p = FirstSuccessPlan.from(
        _in(
          brain: ServiceReadiness.unreachable,
          stt: ServiceReadiness.notConfigured,
        ),
      );
      expect(p.issues.map((i) => i.id), ['brain', 'stt']);
      expect(p.suggestedRequest, isNull);
    });

    test('unconfigured brain explains the fix', () {
      final p = FirstSuccessPlan.from(
        _in(brain: ServiceReadiness.notConfigured),
      );
      expect(p.issues.single.message, contains('Settings'));
    });
  });
}
