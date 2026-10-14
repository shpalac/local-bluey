import 'package:flutter_test/flutter_test.dart';

import 'package:local_bluey/services/idempotent_retry.dart';

class _MemoryStore implements RetryCheckpointStore {
  final Map<String, RetryCheckpoint> values = {};

  @override
  Future<RetryCheckpoint?> read(String operationId) async =>
      values[operationId];

  @override
  Future<void> write(RetryCheckpoint checkpoint) async {
    values[checkpoint.operationId] = checkpoint;
  }
}

void main() {
  test('completed operation is not executed twice', () async {
    final store = _MemoryStore();
    final executor = IdempotentRetryExecutor(store);
    var sends = 0;

    await executor.run<void>(operationId: 'send-1', send: () async => sends++);

    expect(sends, 1);
    await expectLater(
      executor.run<void>(operationId: 'send-1', send: () async => sends++),
      throwsStateError,
    );
    expect(sends, 1);
  });
}
