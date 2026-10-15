import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/benchmark/mac_pilot_metrics.dart';

void main() {
  const metrics = MacPilotMetrics();

  test('ac2 aggregate CPU and false suggestion metrics are reproducible', () {
    final summary = metrics.summarize(
      reviewedSuggestions: 20,
      incorrectSuggestions: 3,
      privacyIncidents: 0,
      retainedRecordsAfterDeletion: 0,
      cpuPercentSamples: [15, 3, 7, 11, 5],
    );
    expect(summary.falseSuggestionRate, closeTo(0.15, 0.00001));
    expect(summary.cpuP50, 7);
    expect(summary.cpuP95, 15);
    expect(summary.hasIncidentOrRetentionFailure, isFalse);
  });

  test('ac2 missing samples remain unknown, not a passing zero', () {
    final summary = metrics.summarize(
      reviewedSuggestions: 0,
      incorrectSuggestions: 0,
      privacyIncidents: 0,
      retainedRecordsAfterDeletion: 0,
      cpuPercentSamples: [],
    );
    expect(summary.falseSuggestionRate, isNull);
    expect(summary.cpuP50, isNull);
    expect(summary.cpuP95, isNull);
  });

  test('ac2 invalid counts and CPU samples fail closed', () {
    for (final badCpu in [double.nan, double.infinity, -0.1]) {
      expect(
        () => metrics.summarize(
          reviewedSuggestions: 1,
          incorrectSuggestions: 0,
          privacyIncidents: 0,
          retainedRecordsAfterDeletion: 0,
          cpuPercentSamples: [badCpu],
        ),
        throwsFormatException,
      );
    }
    expect(
      () => metrics.summarize(
        reviewedSuggestions: 2,
        incorrectSuggestions: 3,
        privacyIncidents: 0,
        retainedRecordsAfterDeletion: 0,
        cpuPercentSamples: [],
      ),
      throwsFormatException,
    );
  });

  test('ac2 privacy incidents and retained records prohibit clean summary', () {
    final summary = metrics.summarize(
      reviewedSuggestions: 10,
      incorrectSuggestions: 1,
      privacyIncidents: 1,
      retainedRecordsAfterDeletion: 2,
      cpuPercentSamples: [125],
    );
    expect(summary.cpuP95, 125);
    expect(summary.hasIncidentOrRetentionFailure, isTrue);
  });
}
