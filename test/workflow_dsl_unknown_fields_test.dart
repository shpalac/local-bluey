import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';

void main() {
  Map<String, dynamic> valid() => {
    'version': WorkflowDefinition.schemaVersion,
    'id': 'safe',
    'trigger': 'manual',
    'steps': [
      {'type': 'notify', 'target': 'done'},
    ],
  };

  test('ac1 unknown top-level workflow fields fail closed', () {
    expect(
      () => WorkflowDefinition.fromJson({
        ...valid(),
        'unreviewed': {'effect': 'side-effect'},
      }),
      throwsFormatException,
    );
  });

  test('ac1 unknown workflow step fields fail closed', () {
    expect(
      () => WorkflowDefinition.fromJson({
        ...valid(),
        'steps': [
          {'type': 'hostAction', 'target': 'openApp', 'unreviewed': true},
        ],
      }),
      throwsFormatException,
    );
  });

  test('ac1 permitted optional fields still round-trip unchanged', () {
    final definition = WorkflowDefinition.fromJson({
      ...valid(),
      'permissions': ['notice'],
      'preconditions': ['ready'],
      'postconditions': ['notified'],
      'retryLimit': 1,
    });

    expect(
      WorkflowDefinition.decode(definition.encode()).toJson(),
      definition.toJson(),
    );
    expect(definition.steps.single.type, 'notify');
    expect(definition.retryLimit, 1);
  });
}
