import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/release_incident_checklist.dart';

void main() {
  const checklist = ReleaseIncidentChecklist();

  test('release dry run rejects missing verification evidence', () {
    final result = checklist.dryRun(
      scenario: ReleaseIncidentScenario.release,
      confirmed: {ReleaseIncidentCheck.ownerAcknowledged},
    );

    expect(result.readyForHumanReview, isFalse);
    expect(result.missing, contains(ReleaseIncidentCheck.artifactVerified));
    expect(result.missing, contains(ReleaseIncidentCheck.egressReviewed));
  });

  test('complete release checklist is review-ready without authorization', () {
    final requirements = checklist.requirementsFor(
      ReleaseIncidentScenario.release,
    );
    final result = checklist.dryRun(
      scenario: ReleaseIncidentScenario.release,
      confirmed: requirements.toSet(),
    );

    expect(result.missing, isEmpty);
    expect(result.readyForHumanReview, isTrue);
    expect(result.executionAuthorized, isFalse);
  });

  test('incident dry runs require containment confirmation', () {
    for (final scenario in [
      ReleaseIncidentScenario.privacyIncident,
      ReleaseIncidentScenario.modelOutage,
    ]) {
      final checks = checklist.requirementsFor(scenario).toSet()
        ..remove(ReleaseIncidentCheck.incidentContainmentReviewed);
      final result = checklist.dryRun(scenario: scenario, confirmed: checks);

      expect(result.readyForHumanReview, isFalse);
      expect(
        result.missing,
        contains(ReleaseIncidentCheck.incidentContainmentReviewed),
      );
    }
  });

  test('migration and rollback cannot omit data compatibility', () {
    for (final scenario in [
      ReleaseIncidentScenario.badMigration,
      ReleaseIncidentScenario.rollback,
    ]) {
      final checks = checklist.requirementsFor(scenario).toSet()
        ..remove(ReleaseIncidentCheck.dataCompatibilityVerified);
      final result = checklist.dryRun(scenario: scenario, confirmed: checks);

      expect(result.readyForHumanReview, isFalse);
      expect(
        result.missing,
        contains(ReleaseIncidentCheck.dataCompatibilityVerified),
      );
    }
  });
}
