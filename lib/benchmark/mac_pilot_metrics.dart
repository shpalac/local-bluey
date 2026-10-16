/// Deterministic aggregate measurements for an opt-in macOS pilot.
///
/// No user content, per-app identifiers, network data or raw observations.
final class MacPilotSummary {
  const MacPilotSummary({
    required this.reviewedSuggestions,
    required this.incorrectSuggestions,
    required this.privacyIncidents,
    required this.retainedRecordsAfterDeletion,
    required this.cpuP50,
    required this.cpuP95,
  });

  final int reviewedSuggestions;
  final int incorrectSuggestions;
  final int privacyIncidents;
  final int retainedRecordsAfterDeletion;
  final double? cpuP50;
  final double? cpuP95;

  /// Unknown when there are no reviewed suggestions, never a claimed zero.
  double? get falseSuggestionRate => reviewedSuggestions == 0
      ? null
      : incorrectSuggestions / reviewedSuggestions;

  /// This is a measurement, not a substitute for signed review or TCC checks.
  bool get hasIncidentOrRetentionFailure =>
      privacyIncidents > 0 || retainedRecordsAfterDeletion > 0;
}

final class MacPilotMetrics {
  const MacPilotMetrics();

  MacPilotSummary summarize({
    required int reviewedSuggestions,
    required int incorrectSuggestions,
    required int privacyIncidents,
    required int retainedRecordsAfterDeletion,
    required Iterable<double> cpuPercentSamples,
  }) {
    if (reviewedSuggestions < 0 ||
        incorrectSuggestions < 0 ||
        incorrectSuggestions > reviewedSuggestions ||
        privacyIncidents < 0 ||
        retainedRecordsAfterDeletion < 0) {
      throw const FormatException('Invalid aggregate pilot counts');
    }
    final cpu = <double>[];
    for (final value in cpuPercentSamples) {
      // Multi-core process CPU may legitimately exceed 100 percent.
      if (!value.isFinite || value < 0) {
        throw const FormatException('Invalid CPU sample');
      }
      cpu.add(value);
    }
    cpu.sort();

    double? nearestRank(int percentile) {
      if (cpu.isEmpty) return null;
      final rank = (cpu.length * percentile + 99) ~/ 100;
      return cpu[rank - 1];
    }

    return MacPilotSummary(
      reviewedSuggestions: reviewedSuggestions,
      incorrectSuggestions: incorrectSuggestions,
      privacyIncidents: privacyIncidents,
      retainedRecordsAfterDeletion: retainedRecordsAfterDeletion,
      cpuP50: nearestRank(50),
      cpuP95: nearestRank(95),
    );
  }
}
