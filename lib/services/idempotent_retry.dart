import 'dart:async';

/// Persisted state for a one-time external effect.
enum RetryPhase { started, completed }

/// Atomic, durable claims are required for external effects.
///
/// A production implementation must commit the claim before returning true,
/// and only one caller/process may claim a given operation ID.
abstract interface class RetryCheckpointStore {
  Future<RetryCheckpoint?> read(String operationId);

  Future<void> write(RetryCheckpoint checkpoint);

  /// Returns false when any claim or completion already exists.
  Future<bool> claim(String operationId);
}

class RetryCheckpoint {
  const RetryCheckpoint({required this.operationId, required this.phase});

  final String operationId;
  final String phase;
}

class RetryCancelled implements Exception {
  const RetryCancelled();
}

/// A cancellation signal is cooperative; it cannot undo a dispatched effect.
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

/// At-most-once invocation, not a guarantee of eventual delivery.
///
/// A failed, timed-out or cancelled send is intentionally left in 'started'
/// state, requiring reconciliation rather than automatic replay.
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

    // Never infer safety from a read/write pair: claims must be atomic.
    if (!await _store.claim(operationId)) {
      throw StateError('Operation already claimed: $operationId');
    }

    // After the claim any error is an uncertain external outcome, including
    // cancellation and timeout. It must never cause automatic replay.
    if (cancellation?.isCancelled ?? false) {
      throw const RetryCancelled();
    }

    final sendFuture = Future<T>.sync(send);
    Future<T> outcome = sendFuture;
    if (timeout != null) {
      outcome = outcome.timeout(timeout);
    }
    if (cancellation != null) {
      outcome = Future.any<T>([
        outcome,
        cancellation.whenCancelled.then<T>((_) => throw const RetryCancelled()),
      ]);
    }

    final result = await outcome;
    // A cancellation after send completion still cannot invalidate the claim.
    if (cancellation?.isCancelled ?? false) {
      throw const RetryCancelled();
    }
    await _store.write(
      RetryCheckpoint(operationId: operationId, phase: 'completed'),
    );
    return result;
  }
}