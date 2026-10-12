import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/retention_purge.dart';

import 'support/fault_injection.dart';

// BLU-054: fault injection over the existing pure RetentionPurger. The
// harness is deterministic and offline. It exercises what exists today; the
// workflow execution state machine and idempotent-retry engine (BLU-016 and
// BLU-019) do not exist yet, so nothing here claims to test them.

class _Store {
  _Store(this.id, this.plan, {this.cls = RetentionClass.activity});
  final String id;
  final FaultPlan plan;
  final RetentionClass cls;

  /// Clears that actually completed (side effects that happened).
  int cleared = 0;

  RetentionTarget get target => RetentionTarget(
    id: id,
    whatEn: 'what $id',
    retentionEn: 'kept $id',
    cls: cls,
    clear: () async {
      await plan.attempt();
      cleared++;
    },
  );
}

void main() {
  for (final fault in [
    Fault.diskFull,
    Fault.crash,
    Fault.timeout,
    Fault.permissionRevoked,
  ]) {
    test(
      '${fault.name}: reported by type only, the rest still purge',
      () async {
        final a = _Store('a', FaultPlan.none());
        final bad = _Store('bad', FaultPlan.first(fault));
        final c = _Store('c', FaultPlan.none());
        final purger = RetentionPurger([a.target, bad.target, c.target]);

        final result = await purger.purge(['a', 'bad', 'c']);

        expect(result.purged, ['a', 'c']);
        expect(result.failed.keys, ['bad']);
        expect(result.ok, isFalse);
        expect(bad.cleared, 0, reason: 'the failed clear had no side effect');
        // Exception type only: no message, path or OS text is copied out.
        final text = result.failed.values.join();
        expect(text, isNot(contains('FAKE-SECRET-PATH')));
        expect(text, isNot(contains('space')));
        expect(text, isNot(contains('denied')));
        expect(purger.busy, isFalse, reason: 'a failure must release the lock');
      },
    );

    test(
      '${fault.name}: retrying only the failed id never repeats clears',
      () async {
        final a = _Store('a', FaultPlan.none());
        final bad = _Store('bad', FaultPlan.first(fault));
        final purger = RetentionPurger([a.target, bad.target]);

        final first = await purger.purge(['a', 'bad']);
        expect(first.failed.keys, ['bad']);

        // The fault has cleared. Retry just the failed store.
        final retry = await purger.purge(first.failed.keys);
        expect(retry.ok, isTrue);
        expect(retry.purged, ['bad']);
        expect(a.cleared, 1, reason: 'the good store was not cleared twice');
        expect(bad.cleared, 1);
      },
    );
  }

  test(
    'a persistent fault keeps failing without side effects or a stuck lock',
    () async {
      final bad = _Store('bad', FaultPlan.first(Fault.diskFull, times: 5));
      final purger = RetentionPurger([bad.target]);
      for (var i = 0; i < 5; i++) {
        final r = await purger.purge(['bad']);
        expect(r.failed, {'bad': 'FileSystemException'});
        expect(purger.busy, isFalse);
      }
      expect(bad.cleared, 0);
      expect((await purger.purge(['bad'])).ok, isTrue);
      expect(bad.cleared, 1);
    },
  );

  test('every store failing differently is reported per store', () async {
    final stores = {
      'disk': _Store('disk', FaultPlan.first(Fault.diskFull)),
      'crash': _Store('crash', FaultPlan.first(Fault.crash)),
      'time': _Store('time', FaultPlan.first(Fault.timeout)),
      'perm': _Store('perm', FaultPlan.first(Fault.permissionRevoked)),
    };
    final purger = RetentionPurger([for (final s in stores.values) s.target]);
    final r = await purger.deleteActivityAndCaches();
    expect(r.purged, isEmpty);
    expect(r.failed, {
      'disk': 'FileSystemException',
      'crash': 'StateError',
      'time': 'TimeoutException',
      'perm': 'FileSystemException',
    });
  });

  test(
    'a faulting protected store is refused and never even attempted',
    () async {
      final routines = _Store(
        'routines',
        FaultPlan.first(Fault.crash),
        cls: RetentionClass.protected,
      );
      final purger = RetentionPurger([routines.target]);
      final r = await purger.deleteActivityAndCaches();
      expect(r.purged, isEmpty);
      expect(r.failed, isEmpty);
      expect(routines.plan.attempts, 0);
    },
  );

  test('KNOWN GAP: a hung store holds the lock; purger has no timeout', () {
    // Documents current behavior, not a desired one. RetentionPurger has no
    // per-store timeout, so a clear that never completes leaves it busy and
    // every later purge is refused as busy until the hung call settles.
    fakeAsync((async) {
      final hung = _Store('hung', FaultPlan.first(Fault.hang));
      final other = _Store('other', FaultPlan.none());
      final purger = RetentionPurger([hung.target, other.target]);
      PurgeResult? first;
      purger.purge(['hung', 'other']).then((r) => first = r);
      async.elapse(const Duration(hours: 24));
      expect(first, isNull, reason: 'still waiting after a simulated day');
      expect(purger.busy, isTrue);

      PurgeResult? second;
      purger.purge(['other']).then((r) => second = r);
      async.flushMicrotasks();
      expect(second!.refused, {'other': 'busy'});
      expect(other.cleared, 0, reason: 'nothing after the hung store ran');
    });
  });
}
