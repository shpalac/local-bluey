/// An offline, side-effect-free gate for release and incident dry runs.
///
/// This is not a deployment, rollback, permission, or incident remediation API.
enum ReleaseIncidentScenario {
  release,
  rollback,
  badMigration,
  privacyIncident,
  modelOutage,
}

enum ReleaseIncidentCheck {
  ownerAcknowledged,
  artifactVerified,
  rollbackPlanReviewed,
  dataCompatibilityVerified,
  safetyGateConfirmed,
  privacyBoundaryReviewed,
  egressReviewed,
  incidentContainmentReviewed,
  recoveryValidated,
}

class ReleaseIncidentChecklistResult {
  const ReleaseIncidentChecklistResult({
    required this.scenario,
    required this.missing,
  });

  final ReleaseIncidentScenario scenario;
  final List<ReleaseIncidentCheck> missing;

  bool get readyForHumanReview => missing.isEmpty;

  // A dry run never authorizes execution, even when all checks pass.
  bool get executionAuthorized => false;
}

class ReleaseIncidentChecklist {
  const ReleaseIncidentChecklist();

  static const Map<ReleaseIncidentScenario, List<ReleaseIncidentCheck>>
  _requirements = {
    ReleaseIncidentScenario.release: [
      ReleaseIncidentCheck.ownerAcknowledged,
      ReleaseIncidentCheck.artifactVerified,
      ReleaseIncidentCheck.rollbackPlanReviewed,
      ReleaseIncidentCheck.dataCompatibilityVerified,
      ReleaseIncidentCheck.safetyGateConfirmed,
      ReleaseIncidentCheck.privacyBoundaryReviewed,
      ReleaseIncidentCheck.egressReviewed,
    ],
    ReleaseIncidentScenario.rollback: [
      ReleaseIncidentCheck.ownerAcknowledged,
      ReleaseIncidentCheck.rollbackPlanReviewed,
      ReleaseIncidentCheck.dataCompatibilityVerified,
      ReleaseIncidentCheck.safetyGateConfirmed,
      ReleaseIncidentCheck.recoveryValidated,
    ],
    ReleaseIncidentScenario.badMigration: [
      ReleaseIncidentCheck.ownerAcknowledged,
      ReleaseIncidentCheck.rollbackPlanReviewed,
      ReleaseIncidentCheck.dataCompatibilityVerified,
      ReleaseIncidentCheck.safetyGateConfirmed,
      ReleaseIncidentCheck.recoveryValidated,
    ],
    ReleaseIncidentScenario.privacyIncident: [
      ReleaseIncidentCheck.ownerAcknowledged,
      ReleaseIncidentCheck.privacyBoundaryReviewed,
      ReleaseIncidentCheck.egressReviewed,
      ReleaseIncidentCheck.incidentContainmentReviewed,
      ReleaseIncidentCheck.safetyGateConfirmed,
    ],
    ReleaseIncidentScenario.modelOutage: [
      ReleaseIncidentCheck.ownerAcknowledged,
      ReleaseIncidentCheck.incidentContainmentReviewed,
      ReleaseIncidentCheck.safetyGateConfirmed,
      ReleaseIncidentCheck.recoveryValidated,
    ],
  };

  ReleaseIncidentChecklistResult dryRun({
    required ReleaseIncidentScenario scenario,
    required Set<ReleaseIncidentCheck> confirmed,
  }) {
    final requiredChecks = _requirements[scenario]!;
    return ReleaseIncidentChecklistResult(
      scenario: scenario,
      missing: List.unmodifiable(
        requiredChecks.where((check) => !confirmed.contains(check)),
      ),
    );
  }

  List<ReleaseIncidentCheck> requirementsFor(
    ReleaseIncidentScenario scenario,
  ) => List.unmodifiable(_requirements[scenario]!);
}
