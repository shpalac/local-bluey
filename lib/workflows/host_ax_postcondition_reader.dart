import '../services/host_control.dart';
import '../services/privacy_guard.dart';
import '../services/safety_gate.dart';
import 'postcondition_verifier.dart';
import 'workflow_execution.dart';

/// Opt-in live AX reader. Never prompts, executes actions or retains captures.
final class HostAxPostconditionReader implements PostconditionReader {
  const HostAxPostconditionReader({
    required this.control,
    required this.gate,
    required this.hasUserConsent,
  });

  final HostControl control;
  final SafetyGate gate;
  final bool Function() hasUserConsent;

  @override
  Future<String?> read(Postcondition condition) async {
    if (condition.kind != PostconditionKind.accessibility ||
        !hasUserConsent() ||
        gate.killed) {
      return null;
    }
    final generation = gate.generation;
    try {
      if (!await control.isTrusted() ||
          gate.killed ||
          gate.generation != generation ||
          !hasUserConsent()) {
        return null;
      }
      // A new snapshot refreshes the host's target ids before resolution.
      final snapshot = await control.snapshot();
      if (gate.killed ||
          gate.generation != generation ||
          !hasUserConsent() ||
          !snapshot.targets.contains(condition.key) ||
          PrivacyGuard.hasSensitive(snapshot.targets)) {
        return null;
      }
      final target = await control.resolveTarget(condition.key);
      if (gate.killed ||
          gate.generation != generation ||
          !hasUserConsent() ||
          PrivacyGuard.hasSensitive(target.text)) {
        return null;
      }
      return target.text;
    } catch (_) {
      // Native failures and missing permissions are unknown, never success.
      return null;
    }
  }
}

/// Explicitly opts an existing workflow host into live AX confirmation.
VerifyingWorkflowHost withHostAxVerification({
  required WorkflowHost delegate,
  required HostControl control,
  required SafetyGate gate,
  required bool Function() hasUserConsent,
  required List<Postcondition> postconditions,
  required Duration timeout,
  VerificationCancellation? cancellation,
}) {
  return VerifyingWorkflowHost(
    delegate: delegate,
    verifier: PostconditionVerifier(
      HostAxPostconditionReader(
        control: control,
        gate: gate,
        hasUserConsent: hasUserConsent,
      ),
    ),
    postconditions: postconditions,
    timeout: timeout,
    cancellation: cancellation,
  );
}
