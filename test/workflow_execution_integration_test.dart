import 'package:flutter_test/flutter_test.dart';

import 'package:local_bluey/services/durable_recovery_store.dart';
import 'package:local_bluey/services/execution_audit.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

void main() {
  test(
    'WorkflowExecution integrates approval host and audit happy path',
    () async {
      final audit = ExecutionAudit();
      final events = <String>[];
      final definition = WorkflowDefinition(
        id: 'blu-016',
        trigger: 'manual',
        steps: const [WorkflowStep(type: 'hostAction', target: 'local')],
      );
      final execution = WorkflowExecution(
        definition,
        _Host(events),
        deadline: const Duration(seconds: 5),
        audit: audit,
      );

      final status = await execution.run();

      expect(status, WorkflowStatus.completed);
      expect(events, ['approve', 'execute', 'verify']);
      expect(audit.entries.any((entry) => entry.status == 'completed'), isTrue);
    },
  );

  test(
    'WorkflowExecution stops after cancellation and does not continue',
    () async {
      final audit = ExecutionAudit();
      final definition = WorkflowDefinition(
        id: 'blu-016-cancel',
        trigger: 'manual',
        steps: const [WorkflowStep(type: 'hostAction', target: 'local')],
      );
      final execution = WorkflowExecution(
        definition,
        _Host([]),
        deadline: const Duration(seconds: 5),
        audit: audit,
      );

      execution.cancel();

      expect(await execution.run(), WorkflowStatus.cancelled);
      expect(audit.stopRequested, isTrue);
    },
  );

  test(
    'WorkflowExecution rejects interrupted restart without replay',
    () async {
      final definition = WorkflowDefinition(
        id: 'blu-016-recovery',
        trigger: 'manual',
        steps: const [WorkflowStep(type: 'hostAction', target: 'local')],
      );
      final execution = WorkflowExecution(
        definition,
        _Host([]),
        deadline: const Duration(seconds: 5),
        recoveryStore: _RecoveryStore(),
      );

      await execution.reconcileStartup();

      expect(execution.requiresManualRecovery, isTrue);
      expect(await execution.run(), WorkflowStatus.failed);
    },
  );
}

final class _Host implements WorkflowHost {
  _Host(this.events);

  final List<String> events;

  @override
  Future<bool> approve(WorkflowStep step) async {
    events.add('approve');
    return true;
  }

  @override
  Future<void> execute(WorkflowStep step) async {
    events.add('execute');
  }

  @override
  Future<bool> verify(WorkflowStep step) async {
    events.add('verify');
    return true;
  }
}

final class _RecoveryStore implements DurableRecoveryStore {
  @override
  Future<void> clear() async {}

  @override
  Future<RecoveryMetadata?> load() async =>
      const RecoveryMetadata(executionId: 'recovery', interrupted: true);

  @override
  Future<void> save(RecoveryMetadata metadata) async {}
}
