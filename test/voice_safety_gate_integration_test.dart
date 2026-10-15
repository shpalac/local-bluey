import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/safety_gate.dart';
import 'package:local_bluey/services/voice_verification.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeVoiceProvider implements VoiceEvidenceProvider {
  int assessments = 0;
  VoiceEvidence evidence = const VoiceEvidence(
    similarity: 1,
    spoofChecked: true,
    spoofSuspected: true,
  );

  @override
  Future<bool> hasMicrophonePermission() async => true;

  @override
  Future<bool> isOfflineReady() async => true;

  @override
  Future<VoiceEvidence> assess(String enrollmentId) async {
    assessments++;
    return evidence;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'spoofed voice at SafetyGate seam still asks for human approval',
    () async {
      final provider = _FakeVoiceProvider();
      final voice = VoiceVerifier(provider: provider);
      voice.enable(enrollmentId: 'test-only', consent: true);
      var confirmations = 0;
      final gate = SafetyGate(
        voiceVerifier: voice,
        onConfirm: (_) async {
          confirmations++;
          return false;
        },
      );

      expect(await gate.authorize('click', {'target_id': 'button'}), isFalse);
      expect(provider.assessments, 1);
      expect(confirmations, 1);
    },
  );

  test('voice provider stays unused without explicit opt-in', () async {
    final provider = _FakeVoiceProvider();
    final voice = VoiceVerifier(provider: provider);
    var confirmations = 0;
    final gate = SafetyGate(
      voiceVerifier: voice,
      onConfirm: (_) async {
        confirmations++;
        return false;
      },
    );

    expect(await gate.authorize('click', {'target_id': 'button'}), isFalse);
    expect(provider.assessments, 0);
    expect(confirmations, 1);
  });
}
