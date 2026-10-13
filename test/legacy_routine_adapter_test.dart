import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/workflows/legacy_routine_LegacyRoutineAdapter.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';

void main() {
  const original = Routine(
    name: 'Reminder',
    trigger: 'remind me',
    instructions: 'notify:Take a break',
  );

  test('compatible routine round-trips without executing or persisting', () {
    final before = original.toJson();
    final workflow = LegacyRoutineAdapter.toWorkflow(original);
    expect(workflow.trigger, 'manual');
    expect(workflow.steps.single.type, 'notify');
    final restored = LegacyRoutineAdapter.toRoutine(WorkflowDefinition.decode(workflow.encode()));
    expect(restored.toJson(), before);
    expect(original.toJson(), before);
  });

  test('generic free-form legacy instructions fail closed', () {
    expect(
      () => LegacyRoutineAdapter.toWorkflow(const Routine(
        name: 'unsafe',
        trigger: 'go',
        instructions: 'run shell command',
      )),
      throwsA(isA<LegacyRoutineConversionException>()),
    );
  });

  test('disabled routines are not accidentally enabled', () {
    expect(
      () => LegacyRoutineAdapter.toWorkflow(const Routine(
        name: 'disabled',
        trigger: 'go',
        instructions: 'notify:hello',
        enabled: false,
      )),
      throwsA(isA<LegacyRoutineConversionException>()),
    );
  });

  test('malformed legacy input is rejected', () {
    expect(
      () => LegacyRoutineAdapter.toWorkflow(const Routine(
        name: '',
        trigger: 'go',
        instructions: 'notify:hello',
      )),
      throwsA(isA<LegacyRoutineConversionException>()),
    );
  });

  test('permissioned, scheduled or multi-step workflows cannot convert', () {
    final base = LegacyRoutineAdapter.toWorkflow(original).toJson();
    for (final changes in <Map<String, dynamic>>[
      {'trigger': 'scheduled'},
      {'permissions': ['hostControl']},
      {'retryLimit': 1},
      {'postconditions': ['done']},
      {'steps': [
        {'type': 'notify', 'target': 'one'},
        {'type': 'notify', 'target': 'two'},
      ]},
    ]) {
      final workflow = WorkflowDefinition.fromJson({...base, ...changes});
      expect(
        () => LegacyRoutineAdapter.toRoutine(workflow),
        throwsA(isA<LegacyRoutineConversionException>()),
      );
    }
  });

  test('host actions and missing trigger metadata are rejected', () {
    final base = LegacyRoutineAdapter.toWorkflow(original).toJson();
    expect(
      () => LegacyRoutineAdapter.toRoutine(WorkflowDefinition.fromJson({
        ...base,
        'steps': [{'type': 'hostAction', 'target': 'openApp'}],
      })),
      throwsA(isA<LegacyRoutineConversionException>()),
    );
    expect(
      () => LegacyRoutineAdapter.toRoutine(WorkflowDefinition.fromJson({
        ...base,
        'preconditions': <String>[],
      })),
      throwsA(isA<LegacyRoutineConversionException>()),
    );
  });

  test('errors do not echo secrets', () {
    const secret = 'token-secret-123';
    try {
      LegacyRoutineAdapter.toWorkflow(const Routine(
        name: 'test',
        trigger: 'go',
        instructions: secret,
      ));
      fail('Expected conversion failure');
    } on LegacyRoutineConversionException catch (error) {
      expect(error.toString(), isNot(contains(secret)));
    }
  });
}
