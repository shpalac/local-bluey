import 'dart:async';

/// Stores durable execution state for operations that must not repeat external
/// side effects after a crash.
abstract interface class RetryCheckpointStore {
  Future<RetryCheckpoint?> read(String operationId);

  Future<void> write(RetryCheckpoint checkpoint);
}

class RetryCheckpoint {
  const RetryCheckpoint({required this.operationId, required this.phase});

  final String operationId;
  final String phase;
}

class IdempotentRetryExecutor {
  IdempotentRetryExecutor(this._store);

  final RetryCheckpointStore _store;

  Future<T> run<T>({
    required String operationId,
    required Future<T> Function() send,
  }) async {
    final existing = await _store.read(operationId);
    if (existing?.phase == 'completed') {
      throw StateError('Operation already completed: $operationId');
    }

    await _store.write(
      RetryCheckpoint(operationId: operationId, phase: 'started'),
    );

    final result = await send();

    await _store.write(
      RetryCheckpoint(operationId: operationId, phase: 'completed'),
    );

    return result;
  }
}
