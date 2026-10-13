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

  static void _validateRoutine(Routine routine) {
    if (routine.name.trim().isEmpty ||
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
