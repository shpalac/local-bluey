import 'package:flutter_test/flutter_test.dart';

import 'package:local_bluey/services/durable_recovery_store.dart';

void main() {
  test('recovery metadata survives simulated restart', () async {
    final store = MemoryDurableRecoveryStore();

    await store.save(
      const RecoveryMetadata(executionId: 'execution-1', interrupted: true),
    );

    final afterRestart = await store.load();

    expect(afterRestart?.executionId, 'execution-1');
    expect(afterRestart?.interrupted, isTrue);
  });

  test('recovery acknowledgement clears pending metadata', () async {
    final store = MemoryDurableRecoveryStore();

    await store.save(
      const RecoveryMetadata(executionId: 'execution-2', interrupted: true),
    );
    await store.clear();

    expect(await store.load(), isNull);
  });
}
