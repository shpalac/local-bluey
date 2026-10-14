import 'dart:async';

import '../services/durable_recovery_store.dart';
import '../services/execution_audit.dart';
import 'workflow_dsl.dart';

enum WorkflowStatus {
  pending,
  running,
  approval,
  verifying,
  completed,
  failed,
  cancelled,
}

abstract interface class WorkflowHost {
  Future<bool> approve(WorkflowStep step);
  Future<void> execute(WorkflowStep step);
  Future<bool> verify(WorkflowStep step);
}

final class WorkflowExecution {
  WorkflowExecution(
    this.definition,
    this.host, {
    required this.deadline,
    this.audit,
    this.recoveryStore,
  });

  final WorkflowDefinition definition;
  final WorkflowHost host;
  final Duration deadline;
  final ExecutionAudit? audit;
  final DurableRecoveryStore? recoveryStore;

  WorkflowStatus status = WorkflowStatus.pending;
  int nextStep = 0;
  String? pendingRecoveryExecutionId;
  bool _cancelled = false;
  Future<WorkflowStatus>? _active;

  Future<void> reconcileStartup() async {
    final metadata = await recoveryStore?.load();
    if (metadata?.interrupted == true) {
      pendingRecoveryExecutionId = metadata!.executionId;
    }
  }

  bool get requiresManualRecovery => pendingRecoveryExecutionId != null;

  void acknowledgeRecovery() {
    pendingRecoveryExecutionId = null;
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    audit?.requestStop();
    if (status != WorkflowStatus.completed && status != WorkflowStatus.failed) {
      status = WorkflowStatus.cancelled;
    }
  }

  Future<WorkflowStatus> run() => _active ??= _run();

  Future<WorkflowStatus> _run() async {
    if (requiresManualRecovery || _cancelled) {
      cancel();
      return status;
    }
    try {
      return await _execute().timeout(deadline, onTimeout: () {
        _cancelled = true;
        status = WorkflowStatus.failed;
        return status;
      });
    } catch (_) {
      status = WorkflowStatus.failed;
      return status;
    }
  }

  Future<WorkflowStatus> _execute() async {
    status = WorkflowStatus.running;
    for (; nextStep < definition.steps.length; nextStep++) {
      if (_cancelled) return status;
      final step = definition.steps[nextStep];
      if (!await host.approve(step)) {
        status = WorkflowStatus.failed;
        return status;
      }
      await host.execute(step);
      if (!await host.verify(step)) {
        status = WorkflowStatus.failed;
        return status;
      }
    }
    status = WorkflowStatus.completed;
    return status;
  }
}
