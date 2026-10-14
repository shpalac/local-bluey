import 'dart:async';

/// Local-only secondary speaker-confidence signal; never an authorization.
enum VoiceVerificationState {
  verified,
  unverified,
  spoofSuspected,
  invalidInput,
  disabled,
  permissionDenied,
  offline,
  timeout,
  cancelled,
  unavailable,
}

/// Evidence supplied by an injected on-device speaker/spoof assessor.
/// A similarity score is not proof of speaker identity or liveness.
class VoiceEvidence {
  const VoiceEvidence({
    required this.similarity,
    required this.spoofChecked,
    required this.spoofSuspected,
  });

  final double similarity;
  final bool spoofChecked;
  final bool spoofSuspected;
}

/// Capability gate. Production integrations must request mic permission
/// independently; no permission prompt, audio capture or network call here.
abstract interface class VoiceEvidenceProvider {
  Future<bool> hasMicrophonePermission();
  Future<bool> isOfflineReady();
  Future<VoiceEvidence> assess(String enrollmentId);
}

/// A per-session and per-consent, default-off, non-persistent assessment.
/// No audio, enrollment embeddings, user IDs or scores are written to disk.
/// A verified result MUST NOT replace SafetyGate's human confirmation.
class VoiceVerifier {
  VoiceVerifier({required this.provider, this.threshold = 0.85}) {
    if (!threshold.isFinite || threshold <= 0 || threshold > 1) {
      throw ArgumentError.value(threshold, 'threshold');
    }
  }

  final VoiceEvidenceProvider provider;

  /// For fake testing only; not an empirically calibrated production threshold.
  final double threshold;

  bool _enabled = false;
  String? _enrollmentId;
  int _revision = 0;
  bool _cancelled = false;

  bool get enabled => _enabled;

  /// Explicit local opt-in; production UI must disclose collection purpose.
  void enable({required String enrollmentId, required bool consent}) {
    if (!consent || enrollmentId.trim().isEmpty || enrollmentId.length > 128) {
      throw ArgumentError('Explicit consent and valid enrollment required');
    }
    _revision++;
    _cancelled = false;
    _enrollmentId = enrollmentId;
    _enabled = true;
  }

  /// Revoke all session authority; late assessor responses are discarded.
  void revoke() {
    _revision++;
    _enabled = false;
    _enrollmentId = null;
    _cancelled = false;
  }

  /// Stop the in-flight attempt without revoking consent.
  void cancel() {
    _revision++;
    _cancelled = true;
  }

  /// A new process/session begins with no voice grant.
  void restart() => revoke();

  Future<VoiceVerificationState> verify({required Duration timeout}) async {
    if (!_enabled || _enrollmentId == null) {
      return VoiceVerificationState.disabled;
    }
    if (_cancelled) return VoiceVerificationState.cancelled;
    if (timeout <= Duration.zero) return VoiceVerificationState.timeout;
    final revision = _revision;
    final id = _enrollmentId!;
    VoiceVerificationState stale() => !_enabled
        ? VoiceVerificationState.disabled
        : VoiceVerificationState.cancelled;
    bool changed() => _revision != revision;

    try {
      // One budget for permission, readiness, and assessment combined.
      final state = await (() async {
        if (!await provider.hasMicrophonePermission()) {
          return VoiceVerificationState.permissionDenied;
        }
        if (changed()) return stale();
        if (!await provider.isOfflineReady()) {
          return VoiceVerificationState.offline;
        }
        if (changed()) return stale();
        final evidence = await provider.assess(id);
        if (changed()) return stale();
        if (!evidence.similarity.isFinite ||
            evidence.similarity < 0 ||
            evidence.similarity > 1) {
          return VoiceVerificationState.invalidInput;
        }
        if (!evidence.spoofChecked) {
          return VoiceVerificationState.unavailable;
        }
        if (evidence.spoofSuspected) {
          return VoiceVerificationState.spoofSuspected;
        }
        return evidence.similarity >= threshold
            ? VoiceVerificationState.verified
            : VoiceVerificationState.unverified;
      })().timeout(timeout);
      return changed() ? stale() : state;
    } on TimeoutException {
      return changed() ? stale() : VoiceVerificationState.timeout;
    } catch (_) {
      return changed() ? stale() : VoiceVerificationState.unavailable;
    }
  }
}
