import 'workflow_dsl.dart';

/// A checkpoint must be committed durably before any external effect.
enum RecoveryPhase { prepared, dispatched, verified }

final class RecoveryCheckpoint {
  const RecoveryCheckpoint({
    required this.workflowId,
    required this.stepIndex,
    required this.phase,
  });

  final String workflowId;
  final int stepIndex;
  final RecoveryPhase phase;

  Map<String, Object> toJson() => {
    'workflowId': workflowId,
    'stepIndex': stepIndex,
    'phase': phase.name,
  };

  factory RecoveryCheckpoint.fromJson(Map<String, dynamic> json) {
    final id = json['workflowId'];
    final index = json['stepIndex'];
    final phase = json['phase'];
    if (id is! String ||
        id.trim().isEmpty ||
        index is! int ||
        index < 0 ||
        phase is! String ||
        !RecoveryPhase.values.any((p) => p.name == phase)) {
      throw const FormatException('Invalid recovery checkpoint');
    }
    return RecoveryCheckpoint(
      workflowId: id,
      stepIndex: index,
      phase: RecoveryPhase.values.byName(phase),
    );
  }
}

abstract interface class RecoveryStore {
  Future<RecoveryCheckpoint?> read(String workflowId);

  /// Implementations must atomically persist before returning.
  Future<void> write(RecoveryCheckpoint checkpoint);
}

/// Only verified checkpoints can advance. Uncertain effects require manual
/// reconciliation; never infer success from a timeout or a process restart.
final class WorkflowRecovery {
  WorkflowRecovery(this.definition, this.store);

  final WorkflowDefinition definition;
  final RecoveryStore store;

  Future<int> nextSafeStep() async {
    final checkpoint = await store.read(definition.id);
    if (checkpoint == null) return 0;
    if (checkpoint.workflowId != definition.id ||
        checkpoint.stepIndex >= definition.steps.length) {
      throw const FormatException('Checkpoint does not match workflow');
    }
    if (checkpoint.phase != RecoveryPhase.verified) {
      throw StateError(
        'External effect outcome unknown: manual reconciliation required',
      );
    }
    return checkpoint.stepIndex + 1;
  }

  Future<void> beforeEffect(int index) async {
    if (index < 0 || index >= definition.steps.length) {
      throw RangeError.index(index, definition.steps);
    }
    final next = await nextSafeStep();
    if (next != index) {
      throw StateError('Duplicate or out-of-order effect');
    }
    await store.write(
      RecoveryCheckpoint(
        workflowId: definition.id,
        stepIndex: index,
        phase: RecoveryPhase.dispatched,
      ),
    );
  }

  Future<void> markVerified(int index) async {
    final checkpoint = await store.read(definition.id);
    if (checkpoint == null ||
        checkpoint.stepIndex != index ||
        checkpoint.phase != RecoveryPhase.dispatched) {
      throw StateError('Missing dispatched checkpoint');
    }
    await store.write(
      RecoveryCheckpoint(
        workflowId: definition.id,
        stepIndex: index,
        phase: RecoveryPhase.verified,
      ),
    );
  }
}
