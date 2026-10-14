import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/durable_retry_checkpoint_store.dart';
import 'package:local_bluey/services/idempotent_retry.dart';

void main() {
  test(
    'checkpoint survives restart and prevents duplicate execution',
    () async {
      final dir = await Directory.systemTemp.createTemp('retry');
      final first = DurableRetryCheckpointStore(dir);
      expect(await first.claim('op'), isTrue);
      final second = DurableRetryCheckpointStore(dir);
      expect(await second.claim('op'), isFalse);
      expect((await second.read('op'))!.phase, RetryPhase.started);
    },
  );

  test('completion uses durable phase', () async {
    final dir = await Directory.systemTemp.createTemp('retry');
    final store = DurableRetryCheckpointStore(dir);
    await store.write(
      const RetryCheckpoint(operationId: 'op', phase: RetryPhase.completed),
    );
    expect((await store.read('op'))!.phase, RetryPhase.completed);
  });

  test('corrupt checkpoint fails explicitly', () async {
    final dir = await Directory.systemTemp.createTemp('retry');
    await File('${dir.path}/op.json').writeAsString('{bad');
    expect(() => DurableRetryCheckpointStore(dir).read('op'), throwsStateError);
  });
}
