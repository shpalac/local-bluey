/// BLU-001: fail-closed decision policy for future opt-in observation.
///
/// This module has no capture side effects and persists no session state.
/// The caller must obtain OS permissions and explicit user consent separately.
enum ObservationDecision { allow, denyConsent, denyPermission, denySensitive, denyUnknown }

enum WindowSensitivity { safe, sensitive, private, unknown }

/// Explicit per-session inputs; never serialize or persist this object.
final class ObservationContext {
  const ObservationContext({
    required this.userConsented,
    required this.osPermissionGranted,
    required this.window,
    required this.sessionActive,
    required this.cancelled,
  });

  final bool userConsented;
  final bool osPermissionGranted;
  final WindowSensitivity window;
  final bool sessionActive;
  final bool cancelled;
}

/// Pure gate: a missing, cancelled or ambiguous condition cannot allow capture.
abstract final class ObservationPolicy {
  static ObservationDecision evaluate(ObservationContext context) {
    if (!context.sessionActive || context.cancelled || !context.userConsented) {
      return ObservationDecision.denyConsent;
    }
    if (!context.osPermissionGranted) {
      return ObservationDecision.denyPermission;
    }
    switch (context.window) {
      case WindowSensitivity.safe:
        return ObservationDecision.allow;
      case WindowSensitivity.sensitive:
      case WindowSensitivity.private:
        return ObservationDecision.denySensitive;
      case WindowSensitivity.unknown:
        return ObservationDecision.denyUnknown;
    }
  }
}
