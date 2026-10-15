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
  Future<void>? _acknowledgement;

  Future<void> reconcileStartup() async {
    final metadata = await recoveryStore?.load();
    if (metadata?.interrupted == true) {
      pendingRecoveryExecutionId = metadata!.executionId;
    }
  }

  bool get requiresManualRecovery => pendingRecoveryExecutionId != null;

  Future<void> acknowledgeRecovery() {
    if (!requiresManualRecovery) return Future<void>.value();
    _acknowledgement = recoveryStore?.clear() ?? Future<void>.value();
    pendingRecoveryExecutionId = null;
    return _acknowledgement!;
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
    if (_cancelled || audit?.stopRequested == true) {
      cancel();
      return status;
    }
    if (_acknowledgement != null || recoveryStore != null) {
      try {
        await _acknowledgement;
        await reconcileStartup();
      } catch (_) {
        status = WorkflowStatus.failed;
        audit?.record('execution', 'recovery_storage_failed');
        return status;
      }
    }
    if (requiresManualRecovery) {
      status = WorkflowStatus.failed;
      return status;
    }
    if (deadline <= Duration.zero) {
      status = WorkflowStatus.failed;
      audit?.record('execution', 'timeout');
      return status;
    }
    try {
      return await _execute().timeout(
        deadline,
        onTimeout: () {
          _cancelled = true;
          status = WorkflowStatus.failed;
          audit?.record('execution', 'timeout');
          return status;
        },
      );
    } catch (_) {
      if (!_cancelled) {
        status = WorkflowStatus.failed;
        audit?.record('execution', 'failed');
      }
      return status;
    }
  }

  Future<WorkflowStatus> _execute() async {
    if (recoveryStore != null) {
      await recoveryStore!.save(
        RecoveryMetadata(executionId: definition.id, interrupted: true),
      );
    }
    status = WorkflowStatus.running;
    audit?.record('execution', 'started');
    for (; nextStep < definition.steps.length; nextStep++) {
      if (_cancelled || audit?.stopRequested == true) {
        cancel();
        return status;
      }
      final step = definition.steps[nextStep];
      status = WorkflowStatus.approval;
      audit?.record('step', 'approval', stepIndex: nextStep);
      final approved = await host.approve(step);
      if (_cancelled || audit?.stopRequested == true) {
        cancel();
        return status;
      }
      if (!approved) {
        status = WorkflowStatus.failed;
        audit?.record('step', 'denied', stepIndex: nextStep);
        return status;
      }
      status = WorkflowStatus.running;
      audit?.record('step', 'started', stepIndex: nextStep);
      await host.execute(step);
      if (_cancelled || audit?.stopRequested == true) {
        cancel();
        return status;
      }
      status = WorkflowStatus.verifying;
      audit?.record('step', 'verifying', stepIndex: nextStep);
      final verified = await host.verify(step);
      if (_cancelled || audit?.stopRequested == true) {
        cancel();
        return status;
      }
      if (!verified) {
        status = WorkflowStatus.failed;
        audit?.record('step', 'failed', stepIndex: nextStep);
        return status;
      }
      // Defer the final step's completion record until recovery cleanup ends.
      if (nextStep + 1 < definition.steps.length) {
        audit?.record('step', 'completed', stepIndex: nextStep);
      }
      status = WorkflowStatus.running;
    }
    if (_cancelled || audit?.stopRequested == true) {
      cancel();
      return status;
    }
    if (recoveryStore != null) await recoveryStore!.clear();
    // A stop during the asynchronous recovery cleanup must never turn
    // a cancelled execution into a successful one.
    if (_cancelled || audit?.stopRequested == true) {
      cancel();
      return status;
    }
    if (definition.steps.isNotEmpty) {
      audit?.record(
        'step',
        'completed',
        stepIndex: definition.steps.length - 1,
      );
    }
    status = WorkflowStatus.completed;
    audit?.record('execution', 'completed');
    return status;
  }
}
