import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/execution_audit.dart';
import 'package:local_bluey/ui/execution_audit_panel.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

void main() {
  WorkflowExecution execution(ExecutionAudit audit) {
    return WorkflowExecution(
      const WorkflowDefinition(
        id: 'audit-live-test',
        trigger: 'manual',
        steps: [WorkflowStep(type: 'notify', target: 'safe')],
      ),
      _InertHost(),
      deadline: const Duration(seconds: 1),
      audit: audit,
    );
  }

  testWidgets('ac1 audit timeline displays newly recorded events', (
    tester,
  ) async {
    final audit = ExecutionAudit();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExecutionAuditPanel(execution: execution(audit), audit: audit),
        ),
      ),
    );

    expect(find.text('approval'), findsNothing);
    audit.record('step', 'approval', stepIndex: 0);
    await tester.pump();
    expect(find.text('approval'), findsOneWidget);
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('safe'), findsNothing);
  });

  testWidgets('ac2 external stop updates button without manual rebuild', (
    tester,
  ) async {
    final audit = ExecutionAudit(maxEntries: 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExecutionAuditPanel(execution: execution(audit), audit: audit),
        ),
      ),
    );

    TextButton stopButton() {
      return tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Stop execution'),
      );
    }

    expect(stopButton().onPressed, isNotNull);

    audit.requestStop();
    await tester.pump();

    expect(stopButton().onPressed, isNull);
    expect(audit.entries, isEmpty);
  });

  testWidgets('ac3 old audit listeners are detached on widget replacement', (
    tester,
  ) async {
    final original = ExecutionAudit();
    final replacement = ExecutionAudit();
    Widget panel(ExecutionAudit audit) {
      return MaterialApp(
        home: Scaffold(
          body: ExecutionAuditPanel(execution: execution(audit), audit: audit),
        ),
      );
    }

    await tester.pumpWidget(panel(original));
    await tester.pumpWidget(panel(replacement));
    original.record('step', 'failed');
    await tester.pump();
    expect(find.text('failed'), findsNothing);

    replacement.record('step', 'approval');
    await tester.pump();
    expect(find.text('approval'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    replacement.record('step', 'failed');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

final class _InertHost implements WorkflowHost {
  @override
  Future<bool> approve(WorkflowStep step) async => false;

  @override
  Future<void> execute(WorkflowStep step) async {}

  @override
  Future<bool> verify(WorkflowStep step) async => false;
}
