import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/durable_retry_checkpoint_store.dart';
import 'package:local_bluey/services/idempotent_retry.dart';

void main() {
  test('checkpoint identifiers cannot escape their storage directory', () async {
    final directory = await Directory.systemTemp.createTemp('retry-id-');
    final store = DurableRetryCheckpointStore(directory);

    await expectLater(store.claim('../outside'), throwsArgumentError);
    await expectLater(store.read('../outside'), throwsArgumentError);
    await expectLater(
      store.write(
        const RetryCheckpoint(
          operationId: '../outside',
          phase: RetryPhase.started,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('checkpoint with mismatched operation id fails closed', () async {
    final directory = await Directory.systemTemp.createTemp('retry-mismatch-');
    await File('${directory.path}/expected.json').writeAsString(
      '{"operationId":"different","phase":"started"}',
    );
    final store = DurableRetryCheckpointStore(directory);

    await expectLater(store.read('expected'), throwsStateError);
    expect(await store.claim('expected'), isFalse);
  });
}
