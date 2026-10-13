import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/postcondition_verifier.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class MemoryReader implements PostconditionReader {
  MemoryReader(this.values);

  final Map<String, String?> values;
  Completer<String?>? pending;

  @override
  Future<String?> read(Postcondition condition) async {
    if (pending != null) return pending!.future;
    return values[condition.key];
  }
}

class ActionHost implements WorkflowHost {
  int executions = 0;
  bool permission = true;

  @override
  Future<bool> approve(WorkflowStep step) async => permission;

  @override
  Future<void> execute(WorkflowStep step) async {
    executions++;
  }

  @override
  Future<bool> verify(WorkflowStep step) async => permission;
}

void main() {
  final ax = Postcondition.parse('ax:button=Done');
  final definition = WorkflowDefinition.fromJson({
    'version': 1,
    'id': 'verification-test',
    'trigger': 'manual',
    'steps': [
      {'type': 'hostAction', 'target': 'button'},
    ],
  });

  test('typed postconditions accept AX, file and tool evidence', () async {
    final conditions = [
      ax,
      Postcondition.parse('file:receipt=present'),
      Postcondition.parse('tool:status=ok'),
    ];
    final verifier = PostconditionVerifier(
      MemoryReader({'button': 'Done', 'receipt': 'present', 'status': 'ok'}),
    );
    expect(
      await verifier.verify(conditions, timeout: const Duration(seconds: 1)),
      VerificationOutcome.confirmed,
    );
  });

  test('unchanged UI after click is not confirmed', () async {
    final host = ActionHost();
    final verifier = PostconditionVerifier(MemoryReader({'button': 'Ready'}));
    final execution = WorkflowExecution(
      definition,
      VerifyingWorkflowHost(
        delegate: host,
        verifier: verifier,
        postconditions: [ax],
        timeout: const Duration(seconds: 1),
      ),
      deadline: const Duration(seconds: 2),
    );
    expect(await execution.run(), WorkflowStatus.failed);
    expect(host.executions, 1);
  });

  test('confirmed evidence permits state machine completion', () async {
    final execution = WorkflowExecution(
      definition,
      VerifyingWorkflowHost(
        delegate: ActionHost(),
        verifier: PostconditionVerifier(MemoryReader({'button': 'Done'})),
        postconditions: [ax],
        timeout: const Duration(seconds: 1),
      ),
      deadline: const Duration(seconds: 2),
    );
    expect(await execution.run(), WorkflowStatus.completed);
  });

  test('missing offline evidence stays inconclusive', () async {
    expect(
      await PostconditionVerifier(
        MemoryReader({}),
      ).verify([ax], timeout: const Duration(seconds: 1)),
      VerificationOutcome.inconclusive,
    );
  });

  test('timeout is inconclusive, including late successful evidence', () async {
    final reader = MemoryReader({})..pending = Completer<String?>();
    final verifier = PostconditionVerifier(reader);
    expect(
      await verifier.verify([ax], timeout: const Duration(milliseconds: 1)),
      VerificationOutcome.inconclusive,
    );
    reader.pending!.complete('Done');
  });

  test('cancelled or late-cancelled observation cannot confirm', () async {
    final cancellation = VerificationCancellation()..cancel();
    final verifier = PostconditionVerifier(MemoryReader({'button': 'Done'}));
    expect(
      await verifier.verify(
        [ax],
        timeout: const Duration(seconds: 1),
        cancellation: cancellation,
      ),
      VerificationOutcome.cancelled,
    );
    final reader = MemoryReader({})..pending = Completer<String?>();
    final lateCancellation = VerificationCancellation();
    final pending = PostconditionVerifier(reader).verify(
      [ax],
      timeout: const Duration(seconds: 1),
      cancellation: lateCancellation,
    );
    await Future<void>.delayed(Duration.zero);
    lateCancellation.cancel();
    reader.pending!.complete('Done');
    expect(await pending, VerificationOutcome.cancelled);
  });

  test('malformed contracts fail before reading', () {
    for (final source in [
      '',
      'ax:',
      'network:status=ok',
      'file:../secret=present',
      'ax:button=',
    ]) {
      expect(() => Postcondition.parse(source), throwsFormatException);
    }
  });

  test('permission denial prevents action', () async {
    final host = ActionHost()..permission = false;
    final execution = WorkflowExecution(
      definition,
      VerifyingWorkflowHost(
        delegate: host,
        verifier: PostconditionVerifier(MemoryReader({'button': 'Done'})),
        postconditions: [ax],
        timeout: const Duration(seconds: 1),
      ),
      deadline: const Duration(seconds: 2),
    );
    expect(await execution.run(), WorkflowStatus.failed);
    expect(host.executions, 0);
  });

  test('missing postconditions fail closed after process restart', () async {
    final verifier = PostconditionVerifier(MemoryReader({'button': 'Done'}));
    expect(
      await verifier.verify([], timeout: const Duration(seconds: 1)),
      VerificationOutcome.inconclusive,
    );
  });

  test('exceptions are inconclusive and never leak exception messages', () async {
    final verifier = PostconditionVerifier(_ThrowingReader());
    expect(
      await verifier.verify([ax], timeout: const Duration(seconds: 1)),
      VerificationOutcome.inconclusive,
    );
  });
}

class _ThrowingReader implements PostconditionReader {
  @override
  Future<String?> read(Postcondition condition) {
    throw StateError('sensitive host details');
  }
}
