import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/execution_audit.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class _CheckpointHost implements WorkflowHost {
  _CheckpointHost(this.audit, {required this.stopAtApproval});
  final ExecutionAudit audit;
  final bool stopAtApproval;
  int approvals = 0;
  int executions = 0;
  int verifications = 0;

  @override
  Future<bool> approve(WorkflowStep step) async {
    approvals++;
    if (stopAtApproval) audit.requestStop();
    return true;
  }

  @override
  Future<void> execute(WorkflowStep step) async {
    executions++;
    if (!stopAtApproval) audit.requestStop();
  }

  @override
  Future<bool> verify(WorkflowStep step) async {
    verifications++;
    return true;
  }
}

WorkflowDefinition _definition() => WorkflowDefinition.fromJson({
  'version': 1,
  'id': 'audit-stop-checkpoint',
  'trigger': 'manual',
  'steps': [
    {'type': 'hostAction', 'target': 'fake'},
    {'type': 'hostAction', 'target': 'fake'},
  ],
});

void main() {
  test('audit stop after approval prevents any host execution', () async {
    final audit = ExecutionAudit();
    final host = _CheckpointHost(audit, stopAtApproval: true);
    final execution = WorkflowExecution(
      _definition(),
      host,
      deadline: const Duration(seconds: 2),
      audit: audit,
    );

    expect(await execution.run(), WorkflowStatus.cancelled);
    expect(host.approvals, 1);
    expect(host.executions, 0);
    expect(host.verifications, 0);
  });

  test(
    'audit stop after execution prevents verification and next step',
    () async {
      final audit = ExecutionAudit();
      final host = _CheckpointHost(audit, stopAtApproval: false);
      final execution = WorkflowExecution(
        _definition(),
        host,
        deadline: const Duration(seconds: 2),
        audit: audit,
      );

      expect(await execution.run(), WorkflowStatus.cancelled);
      expect(host.approvals, 1);
      expect(host.executions, 1);
      expect(host.verifications, 0);
    },
  );
}
