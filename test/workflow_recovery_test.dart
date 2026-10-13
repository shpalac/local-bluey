import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_recovery.dart';

class MemoryRecoveryStore implements RecoveryStore {
  RecoveryCheckpoint? value;
  @override
  Future<RecoveryCheckpoint?> read(String workflowId) async => value;
  @override
  Future<void> write(RecoveryCheckpoint checkpoint) async {
    value = checkpoint;
  }
}

void main() {
  final definition = WorkflowDefinition.fromJson({
    'version': 1,
    'id': 'recovery-test',
    'trigger': 'manual',
    'steps': [
      {'type': 'hostAction', 'target': 'send'},
      {'type': 'notify', 'target': 'done'},
    ],
  });

  test('crash after send fails closed across instances', () async {
    final store = MemoryRecoveryStore();
    await WorkflowRecovery(definition, store).beforeEffect(0);
    final restarted = WorkflowRecovery(definition, store);
    await expectLater(restarted.nextSafeStep(), throwsStateError);
    await expectLater(restarted.beforeEffect(0), throwsStateError);
  });

  test('verified step resumes at next step', () async {
    final store = MemoryRecoveryStore();
    final recovery = WorkflowRecovery(definition, store);
    await recovery.beforeEffect(0);
    await recovery.markVerified(0);
    expect(await WorkflowRecovery(definition, store).nextSafeStep(), 1);
    await expectLater(recovery.beforeEffect(0), throwsStateError);
  });


  test('completed workflow cannot replay an earlier effect', () async {
    final store = MemoryRecoveryStore();
    final recovery = WorkflowRecovery(definition, store);
    await recovery.beforeEffect(0);
    await recovery.markVerified(0);
    await recovery.beforeEffect(1);
    await recovery.markVerified(1);
    expect(await WorkflowRecovery(definition, store).nextSafeStep(), 2);
    await expectLater(recovery.beforeEffect(1), throwsStateError);
  });

  test('malformed checkpoint rejected', () {
    expect(
      () => RecoveryCheckpoint.fromJson({
        'workflowId': '',
        'stepIndex': -1,
        'phase': 'dispatched',
      }),
      throwsFormatException,
    );
  });

  test('cannot verify without dispatched checkpoint', () async {
    final recovery = WorkflowRecovery(definition, MemoryRecoveryStore());
    await expectLater(recovery.markVerified(0), throwsStateError);
  });
}
