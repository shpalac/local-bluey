import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/durable_recovery_store.dart';
import 'package:local_bluey/services/execution_audit.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class _CountingHost implements WorkflowHost {
  int executing = 0;
  @override
  Future<bool> approve(WorkflowStep step) async => true;
  @override
  Future<void> execute(WorkflowStep step) async => executing++;
  @override
  Future<bool> verify(WorkflowStep step) async => true;
}

class _ThrowingRecovery implements DurableRecoveryStore {
  @override
  Future<void> save(RecoveryMetadata metadata) =>
      Future<void>.error(StateError('save failed'));
  @override
  Future<RecoveryMetadata?> load() =>
      Future<RecoveryMetadata?>.error(StateError('load failed'));
  @override
  Future<void> clear() => Future<void>.error(StateError('clear failed'));
}

WorkflowDefinition singleStep(String id) => WorkflowDefinition.fromJson({
  'version': 1,
  'id': id,
  'trigger': 'manual',
  'steps': [
    {'type': 'notify', 'target': 'hello'},
  ],
});

String timeline(ExecutionAudit audit) =>
    audit.entries.map((e) => '${e.step}:${e.status}:${e.stepIndex}').join('|');

const expectedTimeline =
    'execution:started:null|step:approval:0|step:started:0|step:verifying:0'
    '|step:completed:0|execution:completed:null';

void main() {
  test('ac2 identical runs leave byte-identical redacted timelines', () async {
    Future<ExecutionAudit> freshAudit() async {
      final audit = ExecutionAudit();
      final execution = WorkflowExecution(
        singleStep('det'),
        _CountingHost(),
        deadline: const Duration(seconds: 2),
        audit: audit,
      );
      expect(await execution.run(), WorkflowStatus.completed);
      return audit;
    }

    final first = await freshAudit();
    final second = await freshAudit();
    expect(timeline(first), expectedTimeline);
    expect(timeline(second), expectedTimeline);
    expect(timeline(first), timeline(second));
    // The redacted export is deterministic too.
    expect(
      first.exportRedacted(consent: true),
      second.exportRedacted(consent: true),
    );
  });

  test('ac2 storage failure is explicit, redacted and repeatable', () async {
    final audit = ExecutionAudit();
    final host = _CountingHost();
    final execution = WorkflowExecution(
      singleStep('store-fail'),
      host,
      deadline: const Duration(seconds: 2),
      audit: audit,
      recoveryStore: _ThrowingRecovery(),
    );
    expect(await execution.run(), WorkflowStatus.failed);
    final statuses = audit.entries.map((e) => e.status).toSet();
    expect(statuses, contains('recovery_storage_failed'));
    // No silent redaction: the explicit storage verdict is recorded.
    expect(statuses, isNot(contains('[redacted]')));
    // Nothing was executed after the storage failure.
    expect(host.executing, 0);
    final json = audit.exportRedacted(consent: true);
    expect(json, contains('recovery_storage_failed'));

    // A fresh run against the same failing store reports the same failure
    // deterministically.
    final audit2 = ExecutionAudit();
    final execution2 = WorkflowExecution(
      singleStep('store-fail'),
      _CountingHost(),
      deadline: const Duration(seconds: 2),
      audit: audit2,
      recoveryStore: _ThrowingRecovery(),
    );
    expect(await execution2.run(), WorkflowStatus.failed);
    expect(timeline(audit2), timeline(audit));

    // And a restart of the failing execution still fails explicitly.
    expect(await execution.run(), WorkflowStatus.failed);
  });

  test('ac2 cancel is deterministic and drops further work', () async {
    final audit = ExecutionAudit();
    final execution = WorkflowExecution(
      singleStep('cancel'),
      _CountingHost(),
      deadline: const Duration(seconds: 2),
      audit: audit,
    );
    execution.cancel();
    expect(await execution.run(), WorkflowStatus.cancelled);
    expect(execution.status, WorkflowStatus.cancelled);
    final again = await execution.run();
    expect(again, WorkflowStatus.cancelled);
  });

  test(
    'ac2 stop request before the run yields an explicit stale verdict',
    () async {
      final audit = ExecutionAudit();
      audit.requestStop();
      final execution = WorkflowExecution(
        singleStep('stopped'),
        _CountingHost(),
        deadline: const Duration(seconds: 2),
        audit: audit,
      );
      expect(await execution.run(), WorkflowStatus.cancelled);
      // The stop request itself is the last recorded label; the execution
      // never started and nothing further is logged.
      expect(audit.entries.last.status, 'stopped');
    },
  );
}
