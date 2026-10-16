import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';

/// Converts only explicitly supported, non-executable legacy notifications.
///
/// Legacy free-form instructions cannot safely be interpreted as host actions.
/// Conversion never stores data, registers a trigger or executes a workflow.
final class LegacyRoutineAdapter {
  const LegacyRoutineAdapter._();

  static const _prefix = 'notify:';
  static const _triggerPrefix = 'legacy-trigger:';

  static WorkflowDefinition toWorkflow(Routine routine) {
    _validateRoutine(routine);
    if (!routine.enabled) {
      throw const LegacyRoutineConversionException(
        'Disabled routine cannot be converted',
      );
    }
    if (!routine.instructions.startsWith(_prefix)) {
      throw const LegacyRoutineConversionException(
        'Unsupported legacy instructions',
      );
    }
    final message = routine.instructions.substring(_prefix.length).trim();
    if (message.isEmpty) {
      throw const LegacyRoutineConversionException('Empty notification');
    }
    return WorkflowDefinition.fromJson({
      'version': WorkflowDefinition.schemaVersion,
      'id': routine.name,
      'trigger': 'manual',
      'steps': [
        {'type': 'notify', 'target': message},
      ],
      'preconditions': ['$_triggerPrefix${routine.trigger}'],
    });
  }

  /// Previews one stored routine without registration, mutation or execution.
  ///
  /// A missing or duplicate name fails closed. Disabled and unsupported
  /// routines are rejected by [toWorkflow], not silently enabled.
  static WorkflowDefinition previewStored(RoutineStore store, String name) {
    Routine? match;
    for (final routine in store.routines) {
      if (routine.name != name) continue;
      if (match != null) {
        throw const LegacyRoutineConversionException(
          'Ambiguous stored routine',
        );
      }
      match = routine;
    }
    if (match == null) {
      throw const LegacyRoutineConversionException('Stored routine not found');
    }
    return toWorkflow(match);
  }

  static Routine toRoutine(WorkflowDefinition workflow) {
    // Round-trip through schema validation even for manually constructed objects.
    final validated = WorkflowDefinition.fromJson(workflow.toJson());
    if (validated.trigger != 'manual' ||
        validated.steps.length != 1 ||
        validated.steps.single.type != 'notify' ||
        validated.permissions.isNotEmpty ||
        validated.postconditions.isNotEmpty ||
        validated.retryLimit != 0 ||
        validated.preconditions.length != 1 ||
        !validated.preconditions.single.startsWith(_triggerPrefix)) {
      throw const LegacyRoutineConversionException(
        'Unsupported workflow conversion',
      );
    }
    final trigger = validated.preconditions.single.substring(
      _triggerPrefix.length,
    );
    final routine = Routine(
      name: validated.id,
      trigger: trigger,
      instructions: '$_prefix${validated.steps.single.target}',
    );
    _validateRoutine(routine);
    return routine;
  }

  static bool _hasControlCharacters(String value) =>
      value.runes.any((codePoint) => codePoint < 0x20 || codePoint == 0x7f);

  static void _validateRoutine(Routine routine) {
    if (_hasControlCharacters(routine.name) ||
        _hasControlCharacters(routine.trigger) ||
        routine.name.trim().isEmpty ||
        routine.name.length > RoutineStore.maxNameChars ||
        routine.trigger.trim().isEmpty ||
        routine.trigger.length > RoutineStore.maxTriggerChars ||
        routine.instructions.trim().isEmpty ||
        routine.instructions.length > RoutineStore.maxInstructionsChars ||
        routine.trigger != routine.trigger.toLowerCase()) {
      throw const LegacyRoutineConversionException('Invalid legacy routine');
    }
  }
}

/// Generic errors deliberately exclude routine names, instructions and secrets.
final class LegacyRoutineConversionException implements Exception {
  const LegacyRoutineConversionException(this.message);
  final String message;

  @override
  String toString() => message;
}
