import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/durable_retry_checkpoint_store.dart';
import 'package:local_bluey/services/idempotent_retry.dart';

void main() {
  test(
    'ac1 half-created claim never permits a repeated send',
    () async {
    final dir = await Directory.systemTemp.createTemp('retry-partial');
    await File('${dir.path}/send.json').create(exclusive: true);

    final restarted = DurableRetryCheckpointStore(dir);
    expect(await restarted.claim('send'), isFalse);
    await expectLater(restarted.read('send'), throwsStateError);

    var sends = 0;
    await expectLater(
      IdempotentRetryExecutor(restarted).run<void>(
        operationId: 'send',
        send: () async {
          sends++;
        },
      ),
      throwsStateError,
    );
    expect(sends, 0);
    },
  );

  test(
    'ac2 existing stage blocks a concurrent completion write',
    () async {
    final dir = await Directory.systemTemp.createTemp('retry-stage');
    final store = DurableRetryCheckpointStore(dir);
    expect(await store.claim('op'), isTrue);

    final stage = File('${dir.path}/op.json.tmp');
    await stage.writeAsString('unfinished stage');
    await expectLater(
      store.write(
        const RetryCheckpoint(
          operationId: 'op',
          phase: RetryPhase.completed,
        ),
      ),
      throwsA(isA<PathExistsException>()),
    );

    expect(await stage.readAsString(), 'unfinished stage');
    expect((await store.read('op'))?.phase, RetryPhase.started);
    expect(await DurableRetryCheckpointStore(dir).claim('op'), isFalse);
    },
  );

  test(
    'ac3 successful completion leaves no partial stage',
    () async {
    final dir = await Directory.systemTemp.createTemp('retry-complete');
    final store = DurableRetryCheckpointStore(dir);
    expect(await store.claim('op'), isTrue);

    await store.write(
      const RetryCheckpoint(
        operationId: 'op',
        phase: RetryPhase.completed,
      ),
    );

    expect(await File('${dir.path}/op.json.tmp').exists(), isFalse);
    expect(
      (await DurableRetryCheckpointStore(dir).read('op'))?.phase,
      RetryPhase.completed,
    );
    },
  );
}
