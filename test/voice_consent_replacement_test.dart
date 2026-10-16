import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/voice_verification.dart';

void main() {
  test('ac2 rejected replacement revokes previous consent', () async {
    final provider = _Provider();
    final verifier = VoiceVerifier(provider: provider);
    verifier.enable(enrollmentId: 'initial', consent: true);
    expect(verifier.enabled, isTrue);

    expect(
      () => verifier.enable(enrollmentId: 'second', consent: false),
      throwsArgumentError,
    );
    expect(verifier.enabled, isFalse);
    expect(
      await verifier.verify(timeout: const Duration(seconds: 1)),
      VoiceVerificationState.disabled,
    );
    expect(provider.assessments, 0);
  });

  test('ac3 invalid replacement discards an in-flight voice result', () async {
    final provider = _Provider();
    final started = Completer<void>();
    final answer = Completer<VoiceEvidence>();
    provider.onAssess = () {
      started.complete();
      return answer.future;
    };
    final verifier = VoiceVerifier(provider: provider);
    verifier.enable(enrollmentId: 'initial', consent: true);

    final inFlight = verifier.verify(timeout: const Duration(seconds: 1));
    await started.future;
    expect(
      () => verifier.enable(enrollmentId: ' ', consent: true),
      throwsArgumentError,
    );
    answer.complete(
      const VoiceEvidence(
        similarity: 1,
        spoofChecked: true,
        spoofSuspected: false,
      ),
    );

    expect(await inFlight, VoiceVerificationState.disabled);
    expect(verifier.enabled, isFalse);
    expect(provider.assessments, 1);
  });
}

final class _Provider implements VoiceEvidenceProvider {
  int assessments = 0;
  Future<VoiceEvidence> Function()? onAssess;

  @override
  Future<bool> hasMicrophonePermission() async => true;

  @override
  Future<bool> isOfflineReady() async => true;

  @override
  Future<VoiceEvidence> assess(String enrollmentId) async {
    assessments++;
    final callback = onAssess;
    if (callback != null) return callback();
    return const VoiceEvidence(
      similarity: 0.9,
      spoofChecked: true,
      spoofSuspected: false,
    );
  }
}
