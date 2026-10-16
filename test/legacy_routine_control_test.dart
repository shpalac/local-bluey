import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/workflows/legacy_routine_adapter.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';

void main() {
  test('ac2 control characters in legacy trigger metadata fail closed', () {
    final workflow = LegacyRoutineAdapter.toWorkflow(
      const Routine(
        name: 'Reminder',
        trigger: 'remind me',
        instructions: 'notify:Hello',
      ),
    );
    for (final invalidTrigger in [
      'legacy-trigger:run\nmore',
      'legacy-trigger:go\u0000later',
      'legacy-trigger:go\u007f',
    ]) {
      final parsed = WorkflowDefinition.fromJson({
        ...workflow.toJson(),
        'preconditions': [invalidTrigger],
      });
      expect(
        () => LegacyRoutineAdapter.toRoutine(parsed),
        throwsA(isA<LegacyRoutineConversionException>()),
      );
    }
  });

  test('ac3 legacy names and triggers with control bytes never convert', () {
    for (final routine in [
      const Routine(
        name: 'Remind\nNow',
        trigger: 'go',
        instructions: 'notify:Hello',
      ),
      const Routine(
        name: 'Reminder',
        trigger: 'go\tunsafe',
        instructions: 'notify:Hello',
      ),
    ]) {
      expect(
        () => LegacyRoutineAdapter.toWorkflow(routine),
        throwsA(isA<LegacyRoutineConversionException>()),
      );
    }
  });

  test('ac1 ordinary legacy notification round-trips unchanged', () {
    const original = Routine(
      name: 'Reminder',
      trigger: 'remind me',
      instructions: 'notify:Take a break',
    );
    final snapshot = original.toJson();
    final workflow = LegacyRoutineAdapter.toWorkflow(original);
    final converted = LegacyRoutineAdapter.toRoutine(workflow);

    expect(workflow.trigger, 'manual');
    expect(workflow.steps.single.type, 'notify');
    expect(original.toJson(), snapshot);
    expect(converted.toJson(), snapshot);
  });
}
