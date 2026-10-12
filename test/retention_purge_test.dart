import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:local_bluey/services/retention_purge.dart';

class _Fake {
  _Fake(this.id, this.cls, {this.throws = false, this.gate});
  final String id;
  final RetentionClass cls;
  final bool throws;
  final Completer<void>? gate;
  int cleared = 0;

  RetentionTarget get target => RetentionTarget(
    id: id,
    whatEn: 'what $id',
    retentionEn: 'kept $id',
    cls: cls,
    clear: () async {
      if (gate != null) await gate!.future;
      if (throws) throw StateError('secret detail');
      cleared++;
    },
  );
}

void main() {
  late _Fake log, cache, routines, settings;
  late RetentionPurger purger;

  setUp(() {
    log = _Fake('log', RetentionClass.activity);
    cache = _Fake('cache', RetentionClass.cache);
    routines = _Fake('routines', RetentionClass.protected);
    settings = _Fake('settings', RetentionClass.protected);
    purger = RetentionPurger([
      log.target,
      cache.target,
      routines.target,
      settings.target,
    ]);
  });

  test('overview shows each store text as declared and what is purgeable', () {
    final rows = purger.overview;
    expect(rows.map((r) => r.id), ['log', 'cache', 'routines', 'settings']);
    expect(rows.first.retentionEn, 'kept log');
    expect(rows.map((r) => r.purgeable), [true, true, false, false]);
    expect(() => rows.add(rows.first), throwsUnsupportedError);
  });

  test('delete activity and caches leaves protected stores alone', () async {
    final r = await purger.deleteActivityAndCaches();
    expect(r.purged, ['log', 'cache']);
    expect(r.ok, isTrue);
    expect([log.cleared, cache.cleared], [1, 1]);
    expect([routines.cleared, settings.cleared], [0, 0]);
  });

  test('protected and unknown ids are refused, nothing cleared', () async {
    final r = await purger.purge(['routines', 'nope']);
    expect(r.purged, isEmpty);
    expect(r.refused, {'routines': 'protected', 'nope': 'unknown'});
    expect(r.ok, isFalse);
    expect(routines.cleared, 0);
  });

  test('a scoped purge touches only the named store, once', () async {
    final r = await purger.purge(['log', 'log']);
    expect(r.purged, ['log']);
    expect(log.cleared, 1);
    expect(cache.cleared, 0);
  });

  test(
    'a failing store is reported by type only; the rest still run',
    () async {
      final bad = _Fake('bad', RetentionClass.cache, throws: true);
      final p = RetentionPurger([bad.target, log.target]);
      final r = await p.deleteActivityAndCaches();
      expect(r.failed, {'bad': 'StateError'});
      expect(r.failed.toString(), isNot(contains('secret')));
      expect(r.purged, ['log']);
      expect(p.busy, isFalse, reason: 'busy flag released after a failure');
    },
  );

  test(
    'a second purge while one runs is refused as busy, then works',
    () async {
      final gate = Completer<void>();
      final slow = _Fake('slow', RetentionClass.activity, gate: gate);
      final p = RetentionPurger([slow.target, log.target]);
      final first = p.purge(['slow']);
      await Future<void>.delayed(Duration.zero);
      expect(p.busy, isTrue);
      final second = await p.purge(['log']);
      expect(second.refused, {'log': 'busy'});
      expect(log.cleared, 0);
      gate.complete();
      expect((await first).purged, ['slow']);
      expect((await p.purge(['log'])).purged, ['log']);
    },
  );

  test('duplicate store ids are rejected at construction', () {
    expect(
      () => RetentionPurger([log.target, log.target]),
      throwsArgumentError,
    );
  });

  test(
    'fromRegistry: missing classification is protected, explicit ones work',
    () async {
      final cleared = <String>[];
      DataStoreInfo store(String id) => DataStoreInfo(
        id: id,
        sourceFile: 'lib/services/$id.dart',
        whatEn: 'what $id',
        whatHe: 'מה $id',
        where: 'fake',
        retentionEn: 'kept $id',
        retentionHe: 'נשמר $id',
        clear: () async => cleared.add(id),
      );
      final p = RetentionPurger.fromRegistry(
        [
          store('a_log'),
          store('b_cache'),
          store('c_unlisted'),
          store('d_prot'),
        ],
        classes: {
          'a_log': RetentionClass.activity,
          'b_cache': RetentionClass.cache,
          'd_prot': RetentionClass.protected,
          'not_in_registry': RetentionClass.activity,
        },
      );
      expect(p.overview.map((r) => r.purgeable), [true, true, false, false]);
      final r = await p.deleteActivityAndCaches();
      expect(r.purged, ['a_log', 'b_cache']);
      expect(cleared, ['a_log', 'b_cache']);
      final refused = await p.purge([
        'c_unlisted',
        'd_prot',
        'not_in_registry',
      ]);
      expect(refused.refused, {
        'c_unlisted': 'protected',
        'd_prot': 'protected',
        'not_in_registry': 'unknown',
      });
      expect(cleared, ['a_log', 'b_cache'], reason: 'nothing else cleared');
    },
  );

  test('a caller that classifies a store as activity can purge it', () async {
    // The guarantee is conditional on the caller's classification.
    final p = RetentionPurger([routines.target, settings.target]);
    expect((await p.deleteActivityAndCaches()).purged, isEmpty);
    final misclassified = _Fake('routines', RetentionClass.activity);
    final p2 = RetentionPurger([misclassified.target]);
    expect((await p2.purge(['routines'])).purged, ['routines']);
  });

  test('empty request does nothing', () async {
    final r = await purger.purge(const []);
    expect(r.purged, isEmpty);
    expect(r.ok, isTrue);
  });
}
