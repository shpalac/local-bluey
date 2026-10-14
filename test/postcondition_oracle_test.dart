import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/postcondition_verifier.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class MemoryReader implements PostconditionReader {
  MemoryReader(this.values);

  final Map<String, String?> values;
  int reads = 0;

  @override
  Future<String?> read(Postcondition condition) async {
    reads++;
    return values[condition.key];
  }
}

class ActionHost implements WorkflowHost {
  int executeCalls = 0;

  @override
  Future<bool> approve(WorkflowStep step) async => true;

  @override
  Future<void> execute(WorkflowStep step) async {
    executeCalls++;
  }

  @override
  Future<bool> verify(WorkflowStep step) async => true;
}

WorkflowStep _step() => const WorkflowStep(
      type: 'hostAction',
      target: 'send',
    );

Postcondition _expected() => const Postcondition(
      kind: PostconditionKind.toolResponse,
      key: 'result',
      expected: 'done',
    );

void main() {
  test('false success rejects normal host completion with mismatched evidence', () async {
    final reader = MemoryReader({'result': 'wrong'});
    final host = ActionHost();
    final verifier = PostconditionVerifier(reader);
    final workflowHost = VerifyingWorkflowHost(
      delegate: host,
      verifier: verifier,
      postconditions: [_expected()],
      timeout: const Duration(seconds: 1),
    );

    await workflowHost.execute(_step());
    final verified = await workflowHost.verify(_step());

    expect(verified, false);
    expect(host.executeCalls, 1);
  });

  test('ui drift rejects second verification and does not cache confirmation', () async {
    final reader = _ChangingReader(['done', 'changed']);
    final verifier = PostconditionVerifier(reader);

    final first = await verifier.verify(
      [_expected()],
      timeout: const Duration(seconds: 1),
    );
    final second = await verifier.verify(
      [_expected()],
      timeout: const Duration(seconds: 1),
    );

    expect(first, VerificationOutcome.confirmed);
    expect(second, VerificationOutcome.rejected);
    expect(reader.reads, 2);
  });

  test('inconclusive evidence does not permit duplicate action retry', () async {
    final reader = MemoryReader({'result': null});
    final host = ActionHost();
    final verifier = PostconditionVerifier(reader);

    final outcome = await verifier.verify(
      [_expected()],
      timeout: const Duration(seconds: 1),
    );

    expect(outcome, VerificationOutcome.inconclusive);
    expect(host.executeCalls, 0);
  });
}

class _ChangingReader implements PostconditionReader {
  _ChangingReader(this.responses);

  final List<String?> responses;
  int reads = 0;

  @override
  Future<String?> read(Postcondition condition) async {
    final response = responses[reads];
    reads++;
    return response;
  }
}
