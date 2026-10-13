import 'dart:async';

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

/// In-memory, single-flight executor. Host implementations must enforce SafetyGate.
final class WorkflowExecution {
  WorkflowExecution(this.definition, this.host, {required this.deadline, this.audit});

  final WorkflowDefinition definition;
  final WorkflowHost host;
  final Duration deadline;
  final ExecutionAudit? audit;
  WorkflowStatus status = WorkflowStatus.pending;
  int nextStep = 0;
  bool _cancelled = false;
  Future<WorkflowStatus>? _active;

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
      if (_cancelled) return status;
      if (!approved) {
        audit?.record('step', 'denied', stepIndex: nextStep);
        status = WorkflowStatus.failed;
        return status;
      }
      status = WorkflowStatus.running;
      audit?.record('step', 'started', stepIndex: nextStep);
      await host.execute(step);
      if (_cancelled) return status;
      status = WorkflowStatus.verifying;
      audit?.record('step', 'verifying', stepIndex: nextStep);
      if (!await host.verify(step)) {
        if (!_cancelled) {
          status = WorkflowStatus.failed;
          audit?.record('step', 'failed', stepIndex: nextStep);
        }
        return status;
      }
      if (_cancelled) return status;
      audit?.record('step', 'completed', stepIndex: nextStep);
      status = WorkflowStatus.running;
    }
    if (_cancelled || audit?.stopRequested == true) {
      cancel();
      return status;
    }
    status = WorkflowStatus.completed;
    audit?.record('execution', 'completed');
    return status;
  }
}
