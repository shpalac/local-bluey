import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/execution_audit.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

void main() {
  test('cancellation during verification cannot complete or advance', () async {
    final verification = Completer<bool>();
    final verifying = Completer<void>();
    final host = _BlockingVerificationHost(verification, verifying);
    final audit = ExecutionAudit();
    final execution = WorkflowExecution(
      WorkflowDefinition(
        id: 'verification-cancel',
        trigger: 'manual',
        steps: const [
          WorkflowStep(type: 'hostAction', target: 'local'),
          WorkflowStep(type: 'hostAction', target: 'local'),
        ],
      ),
      host,
      deadline: const Duration(seconds: 5),
      audit: audit,
    );

    final result = execution.run();
    await verifying.future;
    expect(execution.status, WorkflowStatus.verifying);
    execution.cancel();
    verification.complete(true);

    expect(await result, WorkflowStatus.cancelled);
    expect(execution.nextStep, 0);
    expect(host.events, ['approve', 'execute', 'verify']);
    expect(
      audit.entries.any((entry) => entry.status == 'completed'),
      isFalse,
    );
  });
}

final class _BlockingVerificationHost implements WorkflowHost {
  _BlockingVerificationHost(this.verification, this.verifying);

  final Completer<bool> verification;
  final Completer<void> verifying;
  final List<String> events = [];

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
  Future<bool> verify(WorkflowStep step) {
    events.add('verify');
    verifying.complete();
    return verification.future;
  }
}
