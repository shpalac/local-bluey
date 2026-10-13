import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/activity_retention_policy.dart';
import 'package:local_bluey/services/data_registry.dart';

void main() {
  DataStoreInfo entry(
    String id, {
    String? source,
    Future<void> Function()? onClear,
  }) => DataStoreInfo(
    id: id,
    sourceFile: source ?? 'lib/services/$id.dart',
    whatEn: id,
    whatHe: id,
    where: 'test-only',
    retentionEn: 'until deleted',
    retentionHe: 'until deleted',
    clear: onClear ?? () async {},
  );

  test('real app registry limits scoped purge to encrypted activity database', () {
    final overview = ActivityRetentionPolicy.forApplication().overview;
    expect(
      overview.where((row) => row.purgeable),
      hasLength(1),
      reason: 'Only the encrypted activity database may be purged',
    );
    expect(overview.any((row) => row.id == 'routines'), isTrue);
    expect(overview.any((row) => row.id == 'settings'), isTrue);
  });

  test('scoped purge leaves routines and credentials untouched', () async {
    final erased = <String>[];
    final registry = [
      entry(
        'activity_store',
        source: 'lib/services/encrypted_activity_store.dart',
        onClear: () async => erased.add('activity_store'),
      ),
      entry('routines', onClear: () async => erased.add('routines')),
      entry('settings', onClear: () async => erased.add('settings')),
      entry('pairing', onClear: () async => erased.add('pairing')),
      entry('model_store', onClear: () async => erased.add('model_store')),
    ];
    final purge = ActivityRetentionPolicy.fromRegistry(registry);
    expect(purge.overview.map((row) => row.purgeable), [
      true,
      false,
      false,
      false,
      false,
    ]);
    final result = await purge.deleteActivityAndCaches();
    expect(result.ok, isTrue);
    expect(result.purged, ['activity_store']);
    expect(erased, ['activity_store']);
    final denied = await purge.purge(['routines', 'settings', 'pairing']);
    expect(
      denied.refused.values.every((reason) => reason == 'protected'),
      isTrue,
    );
    expect(erased, ['activity_store']);
  });

  test(
    'unknown or impersonated activity store cannot delete anything',
    () async {
      var cleared = 0;
      final registry = [
        entry(
          'activity_store',
          source: 'lib/services/routines.dart',
          onClear: () async => cleared++,
        ),
        entry('unknown_cache', onClear: () async => cleared++),
      ];
      final purge = ActivityRetentionPolicy.fromRegistry(registry);
      expect(purge.overview.every((row) => !row.purgeable), isTrue);
      expect((await purge.deleteActivityAndCaches()).purged, isEmpty);
      expect(cleared, 0);
    },
  );

  test(
    'scoped deletion reports failures without leaking exception details',
    () async {
      final registry = [
        entry(
          'activity_store',
          source: 'lib/services/encrypted_activity_store.dart',
          onClear: () async => throw StateError('secret text never in report'),
        ),
        entry(
          'settings',
          onClear: () async => throw StateError('must not be called'),
        ),
      ];
      final outcome = await ActivityRetentionPolicy.fromRegistry(registry)
          .deleteActivityAndCaches();
      expect(outcome.failed, {'activity_store': 'StateError'});
      expect(outcome.failed.toString(), isNot(contains('secret text')));
      expect(outcome.refused, isEmpty);
    },
  );

  test(
    'concurrent activity purge is refused while original is executing',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var deleted = 0;
      final purge = ActivityRetentionPolicy.fromRegistry([
        entry(
          'activity_store',
          source: 'lib/services/encrypted_activity_store.dart',
          onClear: () async {
            started.complete();
            await release.future;
            deleted++;
          },
        ),
      ]);
      final first = purge.deleteActivityAndCaches();
      await started.future;
      final second = await purge.deleteActivityAndCaches();
      expect(second.refused, {'activity_store': 'busy'});
      release.complete();
      expect((await first).purged, ['activity_store']);
      expect(deleted, 1);
    },
  );
}
