import 'routines.dart';

/// A validated, unwired proposal over the existing legacy Routine fields.
/// Does not generate text, store, match, activate or execute anything.
/// Validation of these fields is not privacy or semantic safety approval.
class RoutineProposal {
  RoutineProposal._(this.routine);

  /// Always disabled. Approval and saving are separate caller responsibilities.
  final Routine routine;

  /// Validates already-decoded fields; not a JSON parser or versioned DSL.
  /// Unknown/activation fields are refused rather than silently discarded.
  factory RoutineProposal.fromFields(Map<String, Object?> fields) {
    const keys = {'name', 'trigger', 'instructions'};
    if (fields.length != keys.length || !keys.every(fields.containsKey)) {
      throw const RoutineProposalException();
    }
    String text(String key, int limit) {
      final value = fields[key];
      if (value is! String || value.trim().isEmpty || value.length > limit) {
        throw const RoutineProposalException();
      }
      return value;
    }

    return RoutineProposal._(
      Routine(
        name: text('name', RoutineStore.maxNameChars),
        trigger: text('trigger', RoutineStore.maxTriggerChars).toLowerCase(),
        instructions: text('instructions', RoutineStore.maxInstructionsChars),
        enabled: false,
      ),
    );
  }
}

/// Generic field failure. Does not expose model text or attempted input.
class RoutineProposalException implements Exception {
  const RoutineProposalException();
  @override
  String toString() => 'Routine proposal fields are invalid.';
}
