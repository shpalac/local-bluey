import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/workflow_action_approval.dart';
import 'package:local_bluey/workflows/workflow_approval_grant_store.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class _Prompt implements WorkflowApprovalPrompt {
  @override
  Future<bool> request(WorkflowActionPreview preview) async => true;
}

class _Gate implements WorkflowSafetyCheck {
  @override
  Future<bool> allows(WorkflowActionPreview preview) async => true;
}

class _Delegate implements WorkflowHost {
  int executions = 0;

  @override
  Future<bool> approve(WorkflowStep step) async => true;

  @override
  Future<void> execute(WorkflowStep step) async {
    executions++;
  }

  @override
  Future<bool> verify(WorkflowStep step) async => true;
}

void main() {
  late Directory directory;
  late FileWorkflowApprovalGrantStorage storage;
  late DateTime clock;
  late WorkflowDefinition definition;
  late _Delegate delegate;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('approval-metadata-');
    storage = FileWorkflowApprovalGrantStorage(directory);
    clock = DateTime.utc(2026, 1, 1, 12);
    definition = WorkflowDefinition.fromJson({
      'version': 1,
      'id': 'workflow-approval-restart',
      'trigger': 'manual',
      'permissions': ['accessibility'],
      'steps': [
        {'type': 'hostAction', 'target': 'top-secret-target'},
      ],
    });
    delegate = _Delegate();
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<WorkflowApprovalHost> open() =>
      WorkflowApprovalHost.openWithStorage(
        definition: definition,
        delegate: delegate,
        prompt: _Prompt(),
        safetyGate: _Gate(),
        storage: storage,
        now: () => clock,
      );

  test('revoke persists and prevents host execution after restart', () async {
    final first = await open();
    final action = definition.steps.single;
    expect(await first.approve(action), isTrue);
    await first.revokeStep(0);

    final restored = await open();
    await expectLater(restored.execute(action), throwsStateError);
    expect(delegate.executions, 0);
  });

  test('file-backed approval survives restart and expires with fake clock',
      () async {
    final first = await open();
    final action = definition.steps.single;
    expect(await first.approve(action), isTrue);

    final restored = await open();
    await restored.execute(action);
    expect(delegate.executions, 1);

    clock = clock.add(const Duration(minutes: 6));
    final expired = await open();
    await expectLater(expired.execute(action), throwsStateError);
    expect(delegate.executions, 1);
  });

  test('approval files contain metadata only and never action secrets',
      () async {
    final first = await open();
    expect(await first.approve(definition.steps.single), isTrue);
    final files = directory.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    final record = await files.single.readAsString();
    expect(record, contains('expiresAt'));
    expect(record, contains('revoked'));
    expect(record, isNot(contains('top-secret-target')));
    expect(record, isNot(contains('workflow-approval-restart')));
    expect(files.single.path, isNot(contains('top-secret-target')));
  });

  test('corrupt persisted grants fail closed without host effects', () async {
    final first = await open();
    final action = definition.steps.single;
    expect(await first.approve(action), isTrue);

    final files = directory.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    await files.single.writeAsString('{not-json', flush: true);

    final restored = await open();
    await expectLater(restored.execute(action), throwsStateError);
    expect(delegate.executions, 0);
  });
}
