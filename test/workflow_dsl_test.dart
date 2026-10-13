import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';

void main() {
  final valid = {
    'version': 1,
    'id': 'morning',
    'trigger': 'manual',
    'steps': [
      {'type': 'notify', 'target': 'ready'},
    ],
  };

  test('schema round-trip is stable', () {
    final workflow = WorkflowDefinition.fromJson(valid);
    expect(WorkflowDefinition.decode(workflow.encode()).toJson(), workflow.toJson());
  });

  test('invalid steps fail closed', () {
    expect(
      () => WorkflowDefinition.fromJson({
        ...valid,
        'steps': [
          {'type': 'shell', 'target': 'rm -rf /'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('unsupported schema is rejected', () {
    expect(
      () => WorkflowDefinition.fromJson({...valid, 'version': 2}),
      throwsFormatException,
    );
  });

  test('invalid retry policy is rejected', () {
    expect(
      () => WorkflowDefinition.fromJson({...valid, 'retryLimit': 100}),
      throwsFormatException,
    );
  });

  test('parsing is declarative and never executes host actions', () {
    final workflow = WorkflowDefinition.fromJson({
      ...valid,
      'steps': [
        {'type': 'hostAction', 'target': 'openApp'},
      ],
    });
    expect(workflow.steps.single.type, 'hostAction');
  });
}
