import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/durable_recovery_store.dart';
import 'package:local_bluey/services/execution_audit.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

void main() {
  WorkflowDefinition definition() => const WorkflowDefinition(
    id: 'completion-race',
    trigger: 'manual',
    steps: [WorkflowStep(type: 'hostAction', target: 'local')],
  );

  test('ac1 cancellation during recovery cleanup cannot complete', () async {
    final store = _BlockingClearStore();
    final audit = ExecutionAudit();
    final host = _FakeHost();
    final execution = WorkflowExecution(
      definition(),
      host,
      deadline: const Duration(seconds: 5),
      recoveryStore: store,
      audit: audit,
    );

    final run = execution.run();
    await store.enteredClear.future;
    expect(host.calls, ['approve', 'execute', 'verify']);
    execution.cancel();
    store.releaseClear.complete();

    expect(await run, WorkflowStatus.cancelled);
    expect(execution.status, WorkflowStatus.cancelled);
    expect(audit.entries.any((entry) => entry.status == 'completed'), isFalse);
  });

  test('ac2 audit stop during recovery cleanup fails closed', () async {
    final store = _BlockingClearStore();
    final audit = ExecutionAudit();
    final execution = WorkflowExecution(
      definition(),
      _FakeHost(),
      deadline: const Duration(seconds: 5),
      recoveryStore: store,
      audit: audit,
    );

    final run = execution.run();
    await store.enteredClear.future;
    audit.requestStop();
    store.releaseClear.complete();

    expect(await run, WorkflowStatus.cancelled);
    expect(execution.status, WorkflowStatus.cancelled);
    expect(audit.entries.any((entry) => entry.status == 'completed'), isFalse);
  });
}

final class _BlockingClearStore implements DurableRecoveryStore {
  final enteredClear = Completer<void>();
  final releaseClear = Completer<void>();

  @override
  Future<RecoveryMetadata?> load() async => null;

  @override
  Future<void> save(RecoveryMetadata metadata) async {}

  @override
  Future<void> clear() {
    enteredClear.complete();
    return releaseClear.future;
  }
}

final class _FakeHost implements WorkflowHost {
  final calls = <String>[];

  @override
  Future<bool> approve(WorkflowStep step) async {
    calls.add('approve');
    return true;
  }

  @override
  Future<void> execute(WorkflowStep step) async {
    calls.add('execute');
  }

  @override
  Future<bool> verify(WorkflowStep step) async {
    calls.add('verify');
    return true;
  }
}
