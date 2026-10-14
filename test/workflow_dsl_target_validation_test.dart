import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';

void main() {
  Map<String, dynamic> workflowWithTarget(String target) => {
    'version': 1,
    'id': 'target-validation',
    'trigger': 'manual',
    'steps': [
      {'type': 'hostAction', 'target': target},
    ],
  };

  test('step target rejects embedded control characters', () {
    expect(
      () => WorkflowDefinition.fromJson(
        workflowWithTarget('launch\u0000unexpected'),
      ),
      throwsFormatException,
    );
  });

  test('malformed step target newline is rejected', () {
    expect(
      () => WorkflowDefinition.fromJson(workflowWithTarget('launch\nunsafe')),
      throwsFormatException,
    );
  });
}
