import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/hold_key.dart';
import 'package:local_bluey/services/hold_key_controller.dart';
import 'package:local_bluey/services/data_registry.dart';

const keys = ['holdkey.enabled', 'holdkey.key', 'holdkey.thresholdMs'];

class Storage {
  final data = <String, Object>{};
  String? holdRead, holdWrite, holdRemove, failRead, failWrite, failRemove;
  bool throwing = false;
  Completer<void> entered = Completer<void>(), release = Completer<void>();
  final writes = <String>[];
  Future<Object?> read(String key) async {
    final snapshot = data[key];
    if (holdRead == key) {
      holdRead = null;
      entered.complete();
      await release.future;
    }
    if (failRead == key) throw StateError('private read');
    return snapshot;
  }

  Future<bool> write(String key, Object value) async {
    writes.add(key);
    if (holdWrite == key) {
      holdWrite = null;
      entered.complete();
      await release.future;
    }
    if (failWrite == key) {
      if (throwing) throw StateError('private write');
      return false;
    }
    data[key] = value;
    return true;
  }

  Future<bool> remove(String key) async {
    if (holdRemove == key) {
      holdRemove = null;
      entered.complete();
      await release.future;
    }
    if (failRemove == key) {
      if (throwing) throw StateError('private remove');
      return false;
    }
    data.remove(key);
    return true;
  }

  HoldKeySettings owner() =>
      HoldKeySettings(read: read, write: write, remove: remove);
  void seed() {
    data.addAll({keys[0]: true, keys[1]: 'fn', keys[2]: 600});
  }
}

Future<void> clear() =>
    DataRegistry.stores.firstWhere((s) => s.id == 'hold_key_pref').clear();
Future<void> set(HoldKeySettings c, String key) => switch (key) {
  'holdkey.enabled' => c.setEnabled(true),
  'holdkey.key' => c.setKey(HoldKey.fn),
  _ => c.setThresholdMs(600),
};
void defaults(HoldKeySettings c) {
  expect(c.enabled, false);
  expect(c.key, HoldKey.rightCommand);
  expect(c.thresholdMs, 400);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => HoldKeySettings.debugOverride = null);
  for (final key in keys) {
    test(
      'entered $key write then registry clear invalidates queued old changes',
      () async {
        final s = Storage()..holdWrite = key;
        final c = s.owner();
        addTearDown(c.dispose);
        HoldKeySettings.debugOverride = c;
        final work = set(c, key);
        await s.entered.future;
        defaults(c);
        final queued = Future.wait([
          c.setEnabled(true),
          c.setKey(HoldKey.fn),
          c.setThresholdMs(600),
        ]);
        final deletion = clear();
        s.release.complete();
        await Future.wait([work, queued, deletion]);
        expect(s.data, isEmpty);
        expect(s.writes, [key]);
        defaults(c);
        expect(c.verified, true);
        await Future.wait([
          c.setEnabled(true),
          c.setKey(HoldKey.fn),
          c.setThresholdMs(600),
        ]);
        expect(c.enabled, true);
        expect(c.key, HoldKey.fn);
        expect(c.thresholdMs, 600);
      },
    );
    test(
      'entered $key read cannot publish stale snapshot over clear',
      () async {
        final s = Storage()
          ..seed()
          ..holdRead = key;
        final c = s.owner();
        addTearDown(c.dispose);
        HoldKeySettings.debugOverride = c;
        final seen = <bool>[];
        c.addListener(() => seen.add(c.enabled));
        final work = c.load();
        await s.entered.future;
        final deletion = clear();
        s.release.complete();
        await Future.wait([work, deletion]);
        expect(s.data, isEmpty);
        defaults(c);
        expect(seen, [false]);
      },
    );
    test(
      'entered $key removal orders fresh settings after registry clear',
      () async {
        final s = Storage()
          ..seed()
          ..holdRemove = key;
        final c = s.owner();
        addTearDown(c.dispose);
        await c.load();
        HoldKeySettings.debugOverride = c;
        final deletion = clear();
        await s.entered.future;
        expect(c.enabled, true);
        expect(c.key, HoldKey.fn);
        expect(c.thresholdMs, 600);
        final fresh = Future.wait([
          c.setEnabled(true),
          c.setKey(HoldKey.leftCommand),
          c.setThresholdMs(300),
        ]);
        s.release.complete();
        await Future.wait([deletion, fresh]);
        expect(c.enabled, true);
        expect(c.key, HoldKey.leftCommand);
        expect(c.thresholdMs, 300);
      },
    );
    for (final throwing in [false, true]) {
      test(
        '$key write false/throw=$throwing retains source state and recovers',
        () async {
          final s = Storage()
            ..failWrite = key
            ..throwing = throwing;
          final c = s.owner();
          addTearDown(c.dispose);
          await c.load();
          c.markPermissionMissing(true);
          await expectLater(
            set(c, key),
            throwsA(isA<HoldKeyStorageException>()),
          );
          defaults(c);
          expect(s.data, isEmpty);
          expect(c.verified, true);
          s.failWrite = null;
          await set(c, key);
          expect(
            s.data[key],
            key == keys[0]
                ? true
                : key == keys[1]
                ? 'fn'
                : 600,
          );
        },
      );
      test(
        '$key remove false/throw=$throwing reconciles actual partial deletion',
        () async {
          final s = Storage()
            ..seed()
            ..failRemove = key
            ..throwing = throwing;
          final c = s.owner();
          addTearDown(c.dispose);
          await c.load();
          HoldKeySettings.debugOverride = c;
          await expectLater(clear(), throwsA(isA<HoldKeyStorageException>()));
          final i = keys.indexOf(key);
          for (var j = 0; j < i; j++) {
            expect(s.data.containsKey(keys[j]), false);
          }
          for (var j = i; j < 3; j++) {
            expect(s.data.containsKey(keys[j]), true);
          }
          expect(c.enabled, s.data[keys[0]] ?? false);
          expect(
            c.key,
            s.data[keys[1]] == null ? HoldKey.rightCommand : HoldKey.fn,
          );
          expect(c.thresholdMs, s.data[keys[2]] ?? 400);
          s.failRemove = null;
          await clear();
          expect(s.data, isEmpty);
          defaults(c);
        },
      );
    }
    test(
      '$key failed reconciliation keeps coherent prior snapshot and explicit load recovers',
      () async {
        final s = Storage()..seed();
        final c = s.owner();
        addTearDown(c.dispose);
        await c.load();
        s.failRead = key;
        await expectLater(c.clear(), throwsA(isA<HoldKeyStorageException>()));
        expect(s.data, isEmpty);
        expect(c.enabled, true);
        expect(c.key, HoldKey.fn);
        expect(c.thresholdMs, 600);
        expect(c.verified, false);
        s.failRead = null;
        await c.load();
        defaults(c);
        expect(c.verified, true);
      },
    );
  }
  test('permissionMissing survives load/key/threshold and clears on source-verified disable', () async {
    final s = Storage(), c = s.owner();
    addTearDown(c.dispose);
    await c.load();
    c.markPermissionMissing(true);
    await c.load();
    await c.setKey(HoldKey.fn);
    await c.setThresholdMs(600);
    expect(c.permissionMissing, true);
    await c.setEnabled(false);
    expect(c.permissionMissing, false);
    c.markPermissionMissing(true);
    await c.clear();
    expect(c.permissionMissing, false);
  });
  test('successful enabled write with unreadable reconciliation cannot publish ON until recovery', () async {
    final s = Storage(), c = s.owner();
    addTearDown(c.dispose);
    await c.load();
    s.failRead = keys[1];
    await expectLater(
      c.setEnabled(true),
      throwsA(isA<HoldKeyStorageException>()),
    );
    expect(s.data[keys[0]], true);
    defaults(c);
    expect(c.verified, false);
    s.failRead = null;
    await c.load();
    expect(c.enabled, true);
    expect(c.verified, true);
  });
  test(
    'read failure is generic and invalid input does not access storage',
    () async {
      final s = Storage()..failRead = keys[0];
      final c = s.owner();
      addTearDown(c.dispose);
      await expectLater(
        c.load(),
        throwsA(
          isA<HoldKeyStorageException>().having(
            (e) => e.toString(),
            'safe',
            isNot(contains('private')),
          ),
        ),
      );
      await c.setKey(HoldKey.other);
      await c.setThresholdMs(1);
      expect(s.writes, isEmpty);
      defaults(c);
    },
  );
  test('main load and controller sync callers stay excluded and unchanged', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      source,
      contains('HoldKeySettings.instance.load().then((_) => _syncHoldKey());'),
    );
    expect(
      source,
      contains('void _syncHoldKey() => unawaited(_holdKey.sync());'),
    );
  });
}
