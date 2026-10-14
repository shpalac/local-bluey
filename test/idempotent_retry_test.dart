import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/idempotent_retry.dart';

/// Fake with an atomic claim and state shared between executor instances.
class _MemoryStore implements RetryCheckpointStore {
  final Map<String, RetryCheckpoint> values = {};

  @override
  Future<RetryCheckpoint?> read(String operationId) async => values[operationId];

  @override
  Future<void> write(RetryCheckpoint checkpoint) async {
    values[checkpoint.operationId] = checkpoint;
  }

  @override
  Future<bool> claim(String operationId) async {
    if (values.containsKey(operationId)) return false;
    values[operationId] = RetryCheckpoint(
      operationId: operationId,
      phase: 'started',
    );
    return true;
  }
}

void main() {
  test('completed operation is not executed twice', () async {
    final store = _MemoryStore();
    final executor = IdempotentRetryExecutor(store);
    var sends = 0;

    await executor.run<void>(
      operationId: 'send-1',
      send: () async {
          sends++;
        },
    );

    expect(sends, 1);
    expect((await store.read('send-1'))?.phase, 'completed');
    await expectLater(
      executor.run<void>(
        operationId: 'send-1',
        send: () async {
          sends++;
        },
      ),
      throwsStateError,
    );
    expect(sends, 1);
  });

  test('crash after send before completion fails closed on restart', () async {
    final store = _MemoryStore();
    var sends = 0;
    final executor = IdempotentRetryExecutor(store);

    // A completed external send followed by a failed completion write.
    final failingStore = _FailCompletionStore(store);
    await expectLater(
      IdempotentRetryExecutor(failingStore).run<void>(
        operationId: 'crash',
        send: () async {
          sends++;
        },
      ),
      throwsStateError,
    );
    await expectLater(
      executor.run<void>(
        operationId: 'crash',
        send: () async {
          sends++;
        },
      ),
      throwsStateError,
    );
    expect(sends, 1);
    expect((await store.read('crash'))?.phase, 'started');
  });

  test('concurrent callers have exactly one send', () async {
    final store = _MemoryStore();
    final gate = Completer<void>();
    var sends = 0;
    Future<void> send() async {
      sends++;
      await gate.future;
    }

    final first = IdempotentRetryExecutor(store).run<void>(
      operationId: 'shared',
      send: send,
    );
    await expectLater(
      IdempotentRetryExecutor(store).run<void>(
        operationId: 'shared',
        send: send,
      ),
      throwsStateError,
    );
    gate.complete();
    await first;
    expect(sends, 1);
  });

  test('timeout does not replay an uncertain external send', () async {
    final store = _MemoryStore();
    final pending = Completer<void>();
    var sends = 0;
    await expectLater(
      IdempotentRetryExecutor(store).run<void>(
        operationId: 'timeout',
        send: () {
          sends++;
          return pending.future;
        },
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await expectLater(
      IdempotentRetryExecutor(store).run<void>(
        operationId: 'timeout',
        send: () async {
          sends++;
        },
      ),
      throwsStateError,
    );
    expect(sends, 1);
    pending.complete();
  });

  test('cancellation before claim never sends', () async {
    final cancellation = RetryCancellation()..cancel();
    final store = _MemoryStore();
    var sends = 0;
    await expectLater(
      IdempotentRetryExecutor(store).run<void>(
        operationId: 'cancelled',
        cancellation: cancellation,
        send: () async {
          sends++;
        },
      ),
      throwsA(isA<RetryCancelled>()),
    );
    expect(sends, 0);
    expect(await store.read('cancelled'), isNull);
  });

  test('cancellation during send preserves claim and prevents replay', () async {
    final store = _MemoryStore();
    final cancellation = RetryCancellation();
    final pending = Completer<void>();
    var sends = 0;
    final running = IdempotentRetryExecutor(store).run<void>(
      operationId: 'in-flight',
      cancellation: cancellation,
      send: () {
          sends++;
          return pending.future;
        },
    );
    // Complete the first async claim before cancellation.
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    await expectLater(running, throwsA(isA<RetryCancelled>()));
    await expectLater(
      IdempotentRetryExecutor(store).run<void>(
        operationId: 'in-flight',
        send: () async {
          sends++;
        },
      ),
      throwsStateError,
    );
    expect(sends, 1);
    expect((await store.read('in-flight'))?.phase, 'started');
    pending.complete();
  });

  test('malformed operation IDs and timeouts are rejected', () async {
    final executor = IdempotentRetryExecutor(_MemoryStore());
    await expectLater(
      executor.run<void>(operationId: '  ', send: () async {}),
      throwsArgumentError,
    );
    await expectLater(
      executor.run<void>(
        operationId: 'invalid-timeout',
        timeout: Duration.zero,
        send: () async {},
      ),
      throwsArgumentError,
    );
  });
}

class _FailCompletionStore implements RetryCheckpointStore {
  _FailCompletionStore(this.delegate);
  final _MemoryStore delegate;

  @override
  Future<RetryCheckpoint?> read(String id) => delegate.read(id);

  @override
  Future<bool> claim(String id) => delegate.claim(id);

  @override
  Future<void> write(RetryCheckpoint checkpoint) async {
    if (checkpoint.phase == 'completed') {
      throw StateError('Simulated crash before completion checkpoint');
    }
    await delegate.write(checkpoint);
  }
}
