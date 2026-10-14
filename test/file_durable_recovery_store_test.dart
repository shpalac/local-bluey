import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/durable_recovery_store.dart';
import 'package:local_bluey/services/file_durable_recovery_store.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class _CountingHost implements WorkflowHost {
  int calls = 0;

  @override
  Future<bool> approve(WorkflowStep step) async {
    calls++;
    return true;
  }

  @override
  Future<void> execute(WorkflowStep step) async {
    calls++;
  }

  @override
  Future<bool> verify(WorkflowStep step) async {
    calls++;
    return true;
  }
}

void main() {
  late Directory directory;
  late File metadataFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bluey-recovery-');
    metadataFile = File('${directory.path}/recovery.json');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('file recovery metadata survives new store instance', () async {
    await FileDurableRecoveryStore(metadataFile).save(
      const RecoveryMetadata(executionId: 'exec-573', interrupted: true),
    );
    final restored = await FileDurableRecoveryStore(metadataFile).load();
    expect(restored?.executionId, 'exec-573');
    expect(restored?.interrupted, isTrue);
  });

  test('corrupt recovery metadata fails closed', () async {
    await metadataFile.writeAsString('{"version":1,"executionId":null}');
    await expectLater(
      FileDurableRecoveryStore(metadataFile).load(),
      throwsFormatException,
    );
  });

  test('empty execution IDs are rejected without writing', () async {
    await expectLater(
      FileDurableRecoveryStore(metadataFile).save(
        const RecoveryMetadata(executionId: '', interrupted: true),
      ),
      throwsFormatException,
    );
    expect(await metadataFile.exists(), isFalse);
  });

  test('clear removes acknowledged checkpoint', () async {
    final store = FileDurableRecoveryStore(metadataFile);
    await store.save(
      const RecoveryMetadata(executionId: 'exec-573', interrupted: true),
    );
    await store.clear();
    expect(await FileDurableRecoveryStore(metadataFile).load(), isNull);
  });

  test('restart reconciliation blocks all host actions', () async {
    await FileDurableRecoveryStore(metadataFile).save(
      const RecoveryMetadata(executionId: 'exec-573', interrupted: true),
    );
    final host = _CountingHost();
    final workflow = WorkflowExecution(
      WorkflowDefinition.fromJson({
        'version': 1,
        'id': 'durable-restart',
        'trigger': 'manual',
        'steps': [
          {'type': 'notify', 'target': 'done'},
        ],
      }),
      host,
      deadline: const Duration(seconds: 3),
      recoveryStore: FileDurableRecoveryStore(metadataFile),
    );
    await workflow.reconcileStartup();
    expect(workflow.requiresManualRecovery, isTrue);
    expect(await workflow.run(), WorkflowStatus.failed);
    expect(host.calls, 0);
  });
}
