import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/retention_purge.dart';

RetentionTarget target(String id, Future<void> Function() clear) =>
    RetentionTarget(
      id: id,
      whatEn: id,
      retentionEn: 'test',
      cls: RetentionClass.activity,
      clear: clear,
    );

void main() {
  test(
    'AC-1 timed-out clear is quarantined against duplicate side effects',
    () {
      fakeAsync((clock) {
        final pending = Completer<void>();
        var attempts = 0;
        final purger = RetentionPurger([
          target('slow', () {
            attempts++;
            return pending.future;
          }),
        ], operationTimeout: const Duration(seconds: 1));
        PurgeResult? first;
        purger.purge(['slow']).then((result) => first = result);
        clock.flushMicrotasks();
        expect(attempts, 1);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(first!.failed, {'slow': 'TimeoutException'});
        expect(purger.busy, isFalse);
        PurgeResult? retry;
        purger.purge(['slow']).then((result) => retry = result);
        clock.flushMicrotasks();
        expect(retry!.refused, {'slow': 'indeterminate'});
        expect(attempts, 1);
        pending.complete();
        clock.flushMicrotasks();
        expect(attempts, 1);
      });
    },
  );

  test('AC-2 timed-out store fails explicitly while later stores complete', () {
    fakeAsync((clock) {
      final pending = Completer<void>();
      var completed = 0;
      final purger = RetentionPurger([
        target('hung', () => pending.future),
        target('good', () async {
          completed++;
        }),
      ], operationTimeout: const Duration(milliseconds: 20));
      PurgeResult? result;
      purger.purge(['hung', 'good']).then((value) => result = value);
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 20));
      clock.flushMicrotasks();
      expect(result!.failed, {'hung': 'TimeoutException'});
      expect(result!.purged, ['good']);
      expect(completed, 1);
      expect(purger.busy, isFalse);
    });
  });
}
