import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/durable_recovery_store.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class RecoveryCountingHost implements WorkflowHost {
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

WorkflowExecution recoveryExecution(
  File file,
  RecoveryCountingHost host,
) {
  return WorkflowExecution(
    WorkflowDefinition.fromJson({
      'version': 1,
      'id': 'durable-test',
      'trigger': 'manual',
      'steps': [
        {'type': 'notify', 'target': 'complete'},
      ],
    }),
    host,
    deadline: const Duration(seconds: 5),
    recoveryStore: FileDurableRecoveryStore(file),
  );
}

void main() {
  test('filesystem recovery survives a new store instance', () async {
    final directory = await Directory.systemTemp.createTemp('recovery-ac1-');
    final file = File('${directory.path}/recovery.json');
    await FileDurableRecoveryStore(file).save(
      const RecoveryMetadata(executionId: 'persisted-1', interrupted: true),
    );

    final restored = await FileDurableRecoveryStore(file).load();

    expect(restored?.executionId, 'persisted-1');
    expect(restored?.interrupted, isTrue);
  });

  test('acknowledged recovery remains cleared after restart', () async {
    final directory = await Directory.systemTemp.createTemp('recovery-ac2-');
    final file = File('${directory.path}/recovery.json');
    await FileDurableRecoveryStore(file).save(
      const RecoveryMetadata(executionId: 'interrupted-2', interrupted: true),
    );
    final execution = recoveryExecution(file, RecoveryCountingHost());
    await execution.reconcileStartup();
    expect(execution.requiresManualRecovery, isTrue);

    await execution.acknowledgeRecovery();
    final restarted = recoveryExecution(file, RecoveryCountingHost());
    await restarted.reconcileStartup();

    expect(restarted.requiresManualRecovery, isFalse);
    expect(await FileDurableRecoveryStore(file).load(), isNull);
  });

  test('run checks durable recovery without explicit startup call', () async {
    final directory = await Directory.systemTemp.createTemp('recovery-ac3-');
    final file = File('${directory.path}/recovery.json');
    await FileDurableRecoveryStore(file).save(
      const RecoveryMetadata(executionId: 'interrupted-3', interrupted: true),
    );
    final host = RecoveryCountingHost();
    final execution = recoveryExecution(file, host);

    expect(await execution.run(), WorkflowStatus.failed);
    expect(execution.requiresManualRecovery, isTrue);
    expect(host.approvals, 0);
    expect(host.executions, 0);
    expect(host.verifications, 0);
  });
}
