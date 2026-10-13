import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/workflow_action_approval.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class FakeApprovalPrompt implements WorkflowApprovalPrompt {
  bool accepted = true;
  Completer<bool>? pending;
  final previews = <WorkflowActionPreview>[];

  @override
  Future<bool> request(WorkflowActionPreview preview) async {
    previews.add(preview);
    return pending == null ? accepted : pending!.future;
  }
}

class FakeSafetyCheck implements WorkflowSafetyCheck {
  bool allowed = true;
  Completer<bool>? pending;
  int calls = 0;

  @override
  Future<bool> allows(WorkflowActionPreview preview) async {
    calls++;
    return pending == null ? allowed : pending!.future;
  }
}

class FakeActionHost implements WorkflowHost {
  int actions = 0;
  int verifications = 0;

  @override
  Future<bool> approve(WorkflowStep step) async => true;

  @override
  Future<void> execute(WorkflowStep step) async {
    actions++;
  }

  @override
  Future<bool> verify(WorkflowStep step) async {
    verifications++;
    return true;
  }
}

void main() {
  final definition = WorkflowDefinition.fromJson({
    'version': 1,
    'id': 'workflow',
    'trigger': 'manual',
    'permissions': ['accessibility'],
    'steps': [
      {'type': 'hostAction', 'target': 'test-target'},
    ],
  });

  late FakeApprovalPrompt prompt;
  late FakeSafetyCheck gate;
  late FakeActionHost delegate;
  late WorkflowApprovalHost host;

  setUp(() {
    prompt = FakeApprovalPrompt();
    gate = FakeSafetyCheck();
    delegate = FakeActionHost();
    host = WorkflowApprovalHost(
      definition: definition,
      delegate: delegate,
      prompt: prompt,
      safetyGate: gate,
    );
  });

  Future<WorkflowStatus> run() => WorkflowExecution(
    definition,
    host,
    deadline: const Duration(seconds: 2),
  ).run();

  test('preview declares target, permissions and risk without side effects', () {
    final action = host.preview(0);
    expect(action.workflowId, 'workflow');
    expect(action.stepIndex, 0);
    expect(action.target, 'test-target');
    expect(action.permissions, ['accessibility']);
    expect(action.risky, isTrue);
    expect(delegate.actions, 0);
    expect(() => host.preview(-1), throwsRangeError);
  });

  test('explicit approval and safety gate allow one action', () async {
    expect(await run(), WorkflowStatus.completed);
    expect(prompt.previews, hasLength(1));
    expect(gate.calls, 1);
    expect(delegate.actions, 1);
    expect(delegate.verifications, 1);
  });

  test('denial causes zero side effects', () async {
    prompt.accepted = false;
    expect(await run(), WorkflowStatus.failed);
    expect(delegate.actions, 0);
    expect(gate.calls, 0);
  });

  test('safety denial causes zero side effects', () async {
    gate.allowed = false;
    expect(await run(), WorkflowStatus.failed);
    expect(delegate.actions, 0);
  });

  test('revocation while approval prompt is open denies action', () async {
    prompt.pending = Completer<bool>();
    final outcome = run();
    await Future<void>.delayed(Duration.zero);
    host.revokeAll();
    prompt.pending!.complete(true);
    expect(await outcome, WorkflowStatus.failed);
    expect(delegate.actions, 0);
  });

  test('revocation during asynchronous gate prevents execution', () async {
    gate.pending = Completer<bool>();
    final outcome = run();
    await Future<void>.delayed(Duration.zero);
    host.revokeStep(0);
    gate.pending!.complete(true);
    expect(await outcome, WorkflowStatus.failed);
    expect(delegate.actions, 0);
  });

  test('revocation prevents reuse of an already granted action', () async {
    final step = definition.steps.single;
    expect(await host.approve(step), true);
    host.revokeStep(0);
    await expectLater(host.execute(step), throwsStateError);
    expect(delegate.actions, 0);
  });

  test('restart has no persisted grant', () async {
    final fresh = WorkflowApprovalHost(
      definition: definition,
      delegate: delegate,
      prompt: prompt,
      safetyGate: gate,
    );
    await expectLater(
      fresh.execute(definition.steps.single),
      throwsStateError,
    );
    expect(delegate.actions, 0);
  });

  test('malformed workflow fails before prompting', () {
    expect(
      () => WorkflowApprovalHost(
        definition: const WorkflowDefinition(
          id: '',
          trigger: 'manual',
          steps: [],
        ),
        delegate: delegate,
        prompt: prompt,
        safetyGate: gate,
      ),
      throwsFormatException,
    );
  });

  test('offline prompt fails closed', () async {
    prompt.pending = Completer<bool>()..completeError(StateError('offline'));
    expect(await run(), WorkflowStatus.failed);
    expect(delegate.actions, 0);
  });
}
