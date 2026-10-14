import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/safety_gate.dart';
import 'package:local_bluey/services/voice_verification.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeVoiceProvider implements VoiceEvidenceProvider {
  bool permission = true;
  bool ready = true;
  int calls = 0;
  VoiceEvidence evidence = const VoiceEvidence(
    similarity: 0.95,
    spoofChecked: true,
    spoofSuspected: false,
  );
  Future<VoiceEvidence> Function()? onAssess;

  @override
  Future<bool> hasMicrophonePermission() async => permission;

  @override
  Future<bool> isOfflineReady() async => ready;

  @override
  Future<VoiceEvidence> assess(String enrollmentId) async {
    calls++;
    return onAssess == null ? evidence : await onAssess!();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default off and explicit consent required', () async {
    final fake = FakeVoiceProvider();
    final verifier = VoiceVerifier(provider: fake);
    expect(await verifier.verify(timeout: const Duration(seconds: 1)),
        VoiceVerificationState.disabled);
    expect(() => verifier.enable(enrollmentId: 'speaker', consent: false),
        throwsArgumentError);
    expect(() => verifier.enable(enrollmentId: ' ', consent: true),
        throwsArgumentError);
    expect(fake.calls, 0);
  });

  test('successful secondary signal still requires SafetyGate approval',
      () async {
    final verifier = VoiceVerifier(provider: FakeVoiceProvider());
    verifier.enable(enrollmentId: 'fake-speaker', consent: true);
    expect(await verifier.verify(timeout: const Duration(seconds: 1)),
        VoiceVerificationState.verified);
    var asked = 0;
    final gate = SafetyGate(onConfirm: (_) async {
      asked++;
      return false;
    });
    expect(await gate.authorize('click', {'target_id': 'test'}), isFalse);
    expect(asked, 1);
  });

  test('spoofed voice still asks approval', () async {
    final provider = FakeVoiceProvider()
      ..evidence = const VoiceEvidence(
        similarity: 1,
        spoofChecked: true,
        spoofSuspected: true,
      );
    final verifier = VoiceVerifier(provider: provider);
    verifier.enable(enrollmentId: 'fake-speaker', consent: true);
    expect(await verifier.verify(timeout: const Duration(seconds: 1)),
        VoiceVerificationState.spoofSuspected);
    var asked = 0;
    final gate = SafetyGate(onConfirm: (_) async {
      asked++;
      return false;
    });
    expect(await gate.authorize('type_text', {'text': 'safe fake'}),
        isFalse);
    expect(asked, 1);
  });

  test('invalid score and unavailable spoof evidence deny verification',
      () async {
    final provider = FakeVoiceProvider();
    final verifier = VoiceVerifier(provider: provider);
    verifier.enable(enrollmentId: 'fake-speaker', consent: true);
    provider.evidence = const VoiceEvidence(
        similarity: double.nan, spoofChecked: true, spoofSuspected: false);
    expect(await verifier.verify(timeout: const Duration(seconds: 1)),
        VoiceVerificationState.invalidInput);
    provider.evidence = const VoiceEvidence(
        similarity: 1, spoofChecked: false, spoofSuspected: false);
    expect(await verifier.verify(timeout: const Duration(seconds: 1)),
        VoiceVerificationState.unavailable);
    expect(() => VoiceVerifier(provider: provider, threshold: double.nan),
        throwsArgumentError);
  });

  test('offline and denied microphone permission fail closed', () async {
    final provider = FakeVoiceProvider()..permission = false;
    final verifier = VoiceVerifier(provider: provider);
    verifier.enable(enrollmentId: 'fake-speaker', consent: true);
    expect(await verifier.verify(timeout: const Duration(seconds: 1)),
        VoiceVerificationState.permissionDenied);
    provider.permission = true;
    provider.ready = false;
    expect(await verifier.verify(timeout: const Duration(seconds: 1)),
        VoiceVerificationState.offline);
    expect(provider.calls, 0);
  });

  test('timeout never grants a late response', () async {
    final pending = Completer<VoiceEvidence>();
    final provider = FakeVoiceProvider()..onAssess = () => pending.future;
    final verifier = VoiceVerifier(provider: provider);
    verifier.enable(enrollmentId: 'fake-speaker', consent: true);
    expect(await verifier.verify(timeout: const Duration(milliseconds: 1)),
        VoiceVerificationState.timeout);
    pending.complete(const VoiceEvidence(
        similarity: 1, spoofChecked: true, spoofSuspected: false));
  });

  test('cancellation invalidates in-flight assessment', () async {
    final pending = Completer<VoiceEvidence>();
    final provider = FakeVoiceProvider()..onAssess = () => pending.future;
    final verifier = VoiceVerifier(provider: provider);
    verifier.enable(enrollmentId: 'fake-speaker', consent: true);
    final result = verifier.verify(timeout: const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    verifier.cancel();
    pending.complete(const VoiceEvidence(
        similarity: 1, spoofChecked: true, spoofSuspected: false));
    expect(await result, VoiceVerificationState.cancelled);
    expect(await verifier.verify(timeout: const Duration(seconds: 1)),
        VoiceVerificationState.cancelled);
  });

  test('revocation and restart remove consent and stale results', () async {
    final provider = FakeVoiceProvider();
    final verifier = VoiceVerifier(provider: provider);
    verifier.enable(enrollmentId: 'fake-speaker', consent: true);
    verifier.revoke();
    expect(await verifier.verify(timeout: const Duration(seconds: 1)),
        VoiceVerificationState.disabled);
    verifier.enable(enrollmentId: 'fake-speaker', consent: true);
    verifier.restart();
    expect(verifier.enabled, isFalse);
    expect(await verifier.verify(timeout: const Duration(seconds: 1)),
        VoiceVerificationState.disabled);
  });

  test('no provider or storage called until explicit opt-in', () async {
    final provider = FakeVoiceProvider();
    final verifier = VoiceVerifier(provider: provider);
    expect(await verifier.verify(timeout: const Duration(seconds: 1)),
        VoiceVerificationState.disabled);
    expect(provider.calls, 0);
  });
}
