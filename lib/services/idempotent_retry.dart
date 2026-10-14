import 'dart:async';

enum RetryPhase { started, completed }

abstract interface class RetryCheckpointStore {
  Future<RetryCheckpoint?> read(String operationId);
  Future<void> write(RetryCheckpoint checkpoint);
  Future<bool> claim(String operationId);
}

class RetryCheckpoint {
  const RetryCheckpoint({required this.operationId, required this.phase});

  final String operationId;
  final RetryPhase phase;
}

class RetryCancelled implements Exception {
  const RetryCancelled();
}

class RetryCancellation {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

class IdempotentRetryExecutor {
  IdempotentRetryExecutor(this._store);
  final RetryCheckpointStore _store;

  Future<T> run<T>({
    required String operationId,
    required Future<T> Function() send,
    Duration? timeout,
    RetryCancellation? cancellation,
  }) async {
    if (operationId.trim().isEmpty) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'Must not be empty',
      );
    }
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }
    if (cancellation?.isCancelled ?? false) {
      throw const RetryCancelled();
    }
    if (!await _store.claim(operationId)) {
      throw StateError('Operation already claimed: $operationId');
    }
    if (cancellation?.isCancelled ?? false) {
      throw const RetryCancelled();
    }
    Future<T> outcome = Future<T>.sync(send);
    if (timeout != null) outcome = outcome.timeout(timeout);
    if (cancellation != null) {
      outcome = Future.any<T>([
        outcome,
        cancellation.whenCancelled.then<T>((_) => throw const RetryCancelled()),
      ]);
    }
    final result = await outcome;
    if (cancellation?.isCancelled ?? false) {
      throw const RetryCancelled();
    }
    await _store.write(
      RetryCheckpoint(operationId: operationId, phase: RetryPhase.completed),
    );
    return result;
  }
}
