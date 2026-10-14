import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class FakeHost implements WorkflowHost {
  final events = <String>[];
  bool allowed = true;
  bool verified = true;
  Completer<void>? pending;
  @override
  Future<bool> approve(WorkflowStep step) async {
    events.add('approve');
    return allowed;
  }

  @override
  Future<void> execute(WorkflowStep step) async {
    events.add('execute');
    await pending?.future;
  }

  @override
  Future<bool> verify(WorkflowStep step) async {
    events.add('verify');
    return verified;
  }
}

void main() {
  final definition = WorkflowDefinition.fromJson({
    'version': 1,
    'id': 'test',
    'trigger': 'manual',
    'steps': [
      {'type': 'hostAction', 'target': 'fake'},
    ],
  });
  test('ordered happy path and single-flight', () async {
    final host = FakeHost();
    final execution = WorkflowExecution(
      definition,
      host,
      deadline: const Duration(seconds: 1),
    );
    final first = execution.run();
    final second = execution.run();
    expect(await first, WorkflowStatus.completed);
    expect(await second, WorkflowStatus.completed);
    expect(host.events, ['approve', 'execute', 'verify']);
  });
  test('permission denied fails closed', () async {
    final host = FakeHost()..allowed = false;
    final execution = WorkflowExecution(
      definition,
      host,
      deadline: const Duration(seconds: 1),
    );
    expect(await execution.run(), WorkflowStatus.failed);
    expect(host.events, ['approve']);
  });
  test('verification failure stops workflow', () async {
    final host = FakeHost()..verified = false;
    expect(
      await WorkflowExecution(
        definition,
        host,
        deadline: const Duration(seconds: 1),
      ).run(),
      WorkflowStatus.failed,
    );
  });
  test('cancelled execution never verifies', () async {
    final host = FakeHost()..pending = Completer<void>();
    final execution = WorkflowExecution(
      definition,
      host,
      deadline: const Duration(seconds: 1),
    );
    final result = execution.run();
    await Future<void>.delayed(Duration.zero);
    execution.cancel();
    host.pending!.complete();
    expect(await result, WorkflowStatus.cancelled);
    expect(host.events, ['approve', 'execute']);
  });
  test('timeout fails closed', () async {
    final host = FakeHost()..pending = Completer<void>();
    final execution = WorkflowExecution(
      definition,
      host,
      deadline: const Duration(milliseconds: 1),
    );
    expect(await execution.run(), WorkflowStatus.failed);
    host.pending!.complete();
  });
  test('invalid DSL is rejected before execution', () {
    expect(
      () => WorkflowDefinition.decode('{"version":2}'),
      throwsFormatException,
    );
  });
}
