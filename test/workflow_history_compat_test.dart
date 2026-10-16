import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/execution_audit.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/ui/execution_audit_panel.dart';
import 'package:local_bluey/workflows/legacy_routine_adapter.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class _GreenHost implements WorkflowHost {
  @override
  Future<bool> approve(WorkflowStep step) async => true;
  @override
  Future<void> execute(WorkflowStep step) async {}
  @override
  Future<bool> verify(WorkflowStep step) async => true;
}

WorkflowDefinition routineWorkflow() => LegacyRoutineAdapter.toWorkflow(
  const Routine(
    name: 'Reminder',
    trigger: 'tell me',
    instructions: 'notify:Time to stand up',
  ),
);

void main() {
  test('ac4 routine adapters stay intact while history is recorded', () async {
    const original = Routine(
      name: 'Reminder',
      trigger: 'tell me',
      instructions: 'notify:Time to stand up',
    );
    final before = original.toJson();
    final workflow = routineWorkflow();
    expect(workflow.trigger, 'manual');
    expect(workflow.steps.single.type, 'notify');

    final audit = ExecutionAudit();
    final execution = WorkflowExecution(
      workflow,
      _GreenHost(),
      deadline: const Duration(seconds: 2),
      audit: audit,
    );
    expect(await execution.run(), WorkflowStatus.completed);
    expect(audit.entries, isNotEmpty);

    // The routine and its adapter round-trip are unaffected by the run,
    // the audit capture or the completed history.
    final restored = LegacyRoutineAdapter.toRoutine(
      WorkflowDefinition.decode(workflow.encode()),
    );
    expect(restored.toJson(), before);
    expect(original.toJson(), before);
    expect(
      () => LegacyRoutineAdapter.toWorkflow(
        const Routine(
          name: 'unsafe',
          trigger: 'go',
          instructions: 'run shell command',
        ),
      ),
      throwsA(isA<LegacyRoutineConversionException>()),
    );
  });

  testWidgets('ac4 history panel renders identically across flavors', (
    tester,
  ) async {
    Set<String> firstTimeline = <String>{};
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final audit = ExecutionAudit();
        final execution = WorkflowExecution(
          routineWorkflow(),
          _GreenHost(),
          deadline: const Duration(seconds: 2),
          audit: audit,
        );
        expect(await execution.run(), WorkflowStatus.completed);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ExecutionAuditPanel(execution: execution, audit: audit),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Execution timeline'), findsOneWidget);
        expect(find.text('Export diagnostics'), findsOneWidget);
        expect(find.textContaining('Step'), findsWidgets);
        final rendered = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .whereType<String>()
            .toSet();
        if (firstTimeline.isEmpty) {
          firstTimeline = rendered;
        } else {
          expect(rendered, firstTimeline);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
    expect(firstTimeline, isNotEmpty);
  });
}
