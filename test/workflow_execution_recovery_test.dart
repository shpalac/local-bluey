import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/durable_recovery_store.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class CountingHost implements WorkflowHost {
  int approvals = 0;
  int executions = 0;
  int verifications = 0;

  @override
  Future<bool> approve(WorkflowStep step) async {
    approvals++;
    return true;
  }

  @override
  Future<void> execute(WorkflowStep step) async {
    executions++;
  }

  @override
  Future<bool> verify(WorkflowStep step) async {
    verifications++;
    return true;
  }
}

void main() {
  final definition = WorkflowDefinition.fromJson({
    'version': 1,
    'id': 'recovery-wiring-test',
    'trigger': 'manual',
    'steps': [
      {'type': 'notify', 'target': 'done'},
    ],
  });

  test('interrupted execution surfaces for manual acknowledgement', () async {
    final store = MemoryDurableRecoveryStore();
    await store.save(
      const RecoveryMetadata(executionId: 'exec-9', interrupted: true),
    );
    final execution = WorkflowExecution(
      definition,
      CountingHost(),
      deadline: const Duration(seconds: 5),
      recoveryStore: store,
    );

    await execution.reconcileStartup();

    expect(execution.requiresManualRecovery, isTrue);
    expect(execution.pendingRecoveryExecutionId, 'exec-9');
  });

  test('pending recovery blocks run and never replays host actions', () async {
    final store = MemoryDurableRecoveryStore();
    await store.save(
      const RecoveryMetadata(executionId: 'exec-9', interrupted: true),
    );
    final host = CountingHost();
    final execution = WorkflowExecution(
      definition,
      host,
      deadline: const Duration(seconds: 5),
      recoveryStore: store,
    );
    await execution.reconcileStartup();

    final result = await execution.run();

    expect(result, WorkflowStatus.failed);
    expect(host.approvals, 0);
    expect(host.executions, 0);
    expect(host.verifications, 0);
  });

  test('acknowledged recovery allows execution to proceed', () async {
    final store = MemoryDurableRecoveryStore();
    await store.save(
      const RecoveryMetadata(executionId: 'exec-9', interrupted: true),
    );
    final host = CountingHost();
    final execution = WorkflowExecution(
      definition,
      host,
      deadline: const Duration(seconds: 5),
      recoveryStore: store,
    );
    await execution.reconcileStartup();
    execution.acknowledgeRecovery();

    expect(execution.requiresManualRecovery, isFalse);
    final result = await execution.run();

    expect(result, WorkflowStatus.completed);
    expect(host.executions, 1);
  });

  test('clean startup does not require recovery acknowledgement', () async {
    final host = CountingHost();
    final execution = WorkflowExecution(
      definition,
      host,
      deadline: const Duration(seconds: 5),
      recoveryStore: MemoryDurableRecoveryStore(),
    );

    await execution.reconcileStartup();

    expect(execution.requiresManualRecovery, isFalse);
    expect(await execution.run(), WorkflowStatus.completed);
  });
}
