import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/execution_audit.dart';
import 'package:local_bluey/ui/execution_audit_panel.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class _DenyingHost implements WorkflowHost {
  @override
  Future<bool> approve(WorkflowStep step) async => false;

  @override
  Future<void> execute(WorkflowStep step) async {
    throw StateError('Execution should not run after denial');
  }

  @override
  Future<bool> verify(WorkflowStep step) async => false;
}

void main() {
  testWidgets('AC-1 denied workflow shows actionable redacted failure', (
    tester,
  ) async {
    final audit = ExecutionAudit();
    final definition = WorkflowDefinition.fromJson({
      'version': 1,
      'id': 'workflow-history-test',
      'trigger': 'manual',
      'steps': [
        {'type': 'hostAction', 'target': 'private-user-target'},
      ],
    });
    final execution = WorkflowExecution(
      definition,
      _DenyingHost(),
      deadline: const Duration(seconds: 2),
      audit: audit,
    );

    expect(await execution.run(), WorkflowStatus.failed);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExecutionAuditPanel(execution: execution, audit: audit),
        ),
      ),
    );

    expect(find.byKey(const Key('workflow-failure-message')), findsOneWidget);
    expect(
      find.text('Permission denied. Review approval settings before retrying.'),
      findsOneWidget,
    );
    expect(find.textContaining('private-user-target'), findsNothing);
    expect(find.text('denied'), findsOneWidget);
  });
}
