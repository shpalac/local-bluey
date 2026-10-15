import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/postcondition_verifier.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class _BlankEvidenceReader implements PostconditionReader {
  int reads = 0;

  @override
  Future<String?> read(Postcondition condition) async {
    reads++;
    return '  ';
  }
}

class _CountingHost implements WorkflowHost {
  int actions = 0;

  @override
  Future<bool> approve(WorkflowStep step) async => true;

  @override
  Future<void> execute(WorkflowStep step) async {
    actions++;
  }

  @override
  Future<bool> verify(WorkflowStep step) async => true;
}

void main() {
  test('blank evidence cannot complete workflow', () async {
    final reader = _BlankEvidenceReader();
    final delegate = _CountingHost();
    final host = VerifyingWorkflowHost(
      delegate: delegate,
      verifier: PostconditionVerifier(reader),
      postconditions: [
        const Postcondition(
          kind: PostconditionKind.toolResponse,
          key: 'result',
          expected: 'done',
        ),
      ],
      timeout: const Duration(seconds: 1),
    );
    final execution = WorkflowExecution(
      const WorkflowDefinition(
        id: 'oracle-blank',
        trigger: 'manual',
        steps: [WorkflowStep(type: 'hostAction', target: 'send')],
      ),
      host,
      deadline: const Duration(seconds: 2),
    );

    expect(await execution.run(), WorkflowStatus.failed);
    expect(delegate.actions, 1);
    expect(reader.reads, 1);
    expect(execution.nextStep, 0);
    expect(await execution.run(), WorkflowStatus.failed);
    expect(delegate.actions, 1);
  });

  test('malformed postcondition raises explicit format error', () {
    expect(
      () => Postcondition.parse('tool:=done'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => Postcondition.parse('network:result=done'),
      throwsA(isA<FormatException>()),
    );
  });
}
