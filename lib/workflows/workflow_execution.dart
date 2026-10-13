import 'dart:async';

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
  WorkflowExecution(this.definition, this.host, {required this.deadline});

  final WorkflowDefinition definition;
  final WorkflowHost host;
  final Duration deadline;
  WorkflowStatus status = WorkflowStatus.pending;
  int nextStep = 0;
  bool _cancelled = false;
  Future<WorkflowStatus>? _active;

  void cancel() {
    _cancelled = true;
    if (status != WorkflowStatus.completed && status != WorkflowStatus.failed) {
      status = WorkflowStatus.cancelled;
    }
  }

  Future<WorkflowStatus> run() => _active ??= _run();

  Future<WorkflowStatus> _run() async {
    if (_cancelled) return status;
    if (deadline <= Duration.zero) {
      status = WorkflowStatus.failed;
      return status;
    }
    try {
      return await _execute().timeout(
        deadline,
        onTimeout: () {
          _cancelled = true;
          status = WorkflowStatus.failed;
          return status;
        },
      );
    } catch (_) {
      if (!_cancelled) status = WorkflowStatus.failed;
      return status;
    }
  }

  Future<WorkflowStatus> _execute() async {
    status = WorkflowStatus.running;
    for (; nextStep < definition.steps.length; nextStep++) {
      if (_cancelled) return status;
      final step = definition.steps[nextStep];
      status = WorkflowStatus.approval;
      final approved = await host.approve(step);
      if (_cancelled) return status;
      if (!approved) {
        status = WorkflowStatus.failed;
        return status;
      }
      status = WorkflowStatus.running;
      await host.execute(step);
      if (_cancelled) return status;
      status = WorkflowStatus.verifying;
      if (!await host.verify(step)) {
        if (!_cancelled) status = WorkflowStatus.failed;
        return status;
      }
      if (_cancelled) return status;
      status = WorkflowStatus.running;
    }
    status = WorkflowStatus.completed;
    return status;
  }
}
