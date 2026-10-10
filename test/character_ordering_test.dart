import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/characters.dart';
import 'package:local_bluey/services/data_registry.dart';

class Storage {
  String? value;
  bool readFails = false,
      writeFails = false,
      removeFails = false,
      throws = false;
  Completer<void>? readEntered,
      readRelease,
      writeEntered,
      writeRelease,
      removeEntered,
      removeRelease;
  final writes = <String>[];
  Future<String?> read() async {
    final snapshot = value;
    final e = readEntered, r = readRelease;
    readEntered = readRelease = null;
    if (e != null) {
      e.complete();
      await r!.future;
    }
    if (readFails) throw StateError('private read');
    return snapshot;
  }

  Future<bool> write(String id) async {
    writes.add(id);
    final e = writeEntered, r = writeRelease;
    writeEntered = writeRelease = null;
    if (e != null) {
      e.complete();
      await r!.future;
    }
    if (writeFails) {
      if (throws) throw StateError('private write');
      return false;
    }
    value = id;
    return true;
  }

  Future<bool> remove() async {
    final e = removeEntered, r = removeRelease;
    removeEntered = removeRelease = null;
    if (e != null) {
      e.complete();
      await r!.future;
    }
    if (removeFails) {
      if (throws) throw StateError('private remove');
      return false;
    }
    value = null;
    return true;
  }

  CharacterStore owner() =>
      CharacterStore(read: read, write: write, remove: remove);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => CharacterStore.debugOverride = null);
  Future<void> registryClear() =>
      DataRegistry.stores.firstWhere((s) => s.id == 'character').clear();
  test('entered write, queued old choice, registry clear, fresh choice remain ordered', () async {
    final s = Storage(), e = Completer<void>(), r = Completer<void>();
    final c = s.owner();
    addTearDown(c.current.dispose);
    CharacterStore.debugOverride = c;
    s.writeEntered = e;
    s.writeRelease = r;
    final entered = c.select('captain');
    await e.future;
    expect(c.current.value.id, 'bluey');
    final old = c.select('obsolete'),
        clear = registryClear(),
        fresh = c.select('captain');
    r.complete();
    await Future.wait([entered, old, clear, fresh]);
    expect(s.writes, ['captain', 'captain']);
    expect(s.value, 'captain');
    expect(c.current.value.id, 'captain');
    expect(c.verified, true);
  });
  test(
    'entered clear precedes fresh choice; default not published early',
    () async {
      final s = Storage()..value = 'captain';
      final c = s.owner();
      addTearDown(c.current.dispose);
      await c.load();
      CharacterStore.debugOverride = c;
      final e = Completer<void>(), r = Completer<void>();
      s.removeEntered = e;
      s.removeRelease = r;
      final clear = registryClear();
      await e.future;
      expect(c.current.value.id, 'captain');
      final fresh = c.select('bluey');
      r.complete();
      await Future.wait([clear, fresh]);
      expect(s.value, 'bluey');
      expect(c.current.value.id, 'bluey');
    },
  );
  for (final fresh in [false, true]) {
    test(
      'entered old read cannot publish over registry clear fresh=$fresh',
      () async {
        final s = Storage()..value = 'captain';
        final c = s.owner();
        addTearDown(c.current.dispose);
        CharacterStore.debugOverride = c;
        final seen = <String>[];
        c.current.addListener(() => seen.add(c.current.value.id));
        final e = Completer<void>(), r = Completer<void>();
        s.readEntered = e;
        s.readRelease = r;
        final load = c.load();
        await e.future;
        final clear = registryClear();
        final choice = fresh ? c.select('captain') : Future<void>.value();
        r.complete();
        await Future.wait([load, clear, choice]);
        expect(s.value, fresh ? 'captain' : null);
        expect(c.current.value.id, fresh ? 'captain' : 'bluey');
        expect(seen, fresh ? ['captain'] : isEmpty);
      },
    );
  }
  for (final throwing in [false, true]) {
    for (final operation in ['write', 'remove']) {
      test(
        '$operation false/throw=$throwing retains actual state and retry works',
        () async {
          final s = Storage()
            ..value = 'captain'
            ..throws = throwing;
          final c = s.owner();
          addTearDown(c.current.dispose);
          await c.load();
          s.writeFails = operation == 'write';
          s.removeFails = operation == 'remove';
          final result = operation == 'write' ? c.select('bluey') : c.clear();
          await expectLater(result, throwsA(isA<CharacterStorageException>()));
          expect(c.current.value.id, 'captain');
          expect(s.value, 'captain');
          expect(c.verified, true);
          s.writeFails = s.removeFails = false;
          await (operation == 'write' ? c.select('bluey') : c.clear());
          expect(c.current.value.id, 'bluey');
          expect(c.verified, true);
        },
      );
    }
  }
  for (final op in ['load', 'write', 'remove']) {
    test(
      '$op read uncertainty retains last verified choice and explicit load recovers',
      () async {
        final s = Storage()..value = 'captain';
        final c = s.owner();
        addTearDown(c.current.dispose);
        await c.load();
        s.readFails = true;
        await expectLater(
          op == 'load'
              ? c.load()
              : op == 'write'
              ? c.select('bluey')
              : c.clear(),
          throwsA(isA<CharacterStorageException>()),
        );
        expect(c.current.value.id, 'captain');
        expect(c.verified, false);
        expect(
          s.value,
          op == 'load'
              ? 'captain'
              : op == 'write'
              ? 'bluey'
              : null,
        );
        s.readFails = false;
        await c.load();
        expect(c.current.value.id, op == 'load' ? 'captain' : 'bluey');
        expect(c.verified, true);
      },
    );
  }
  test('failed registry clear reports safe error and actual retained choice then recovers', () async {
    final s = Storage()
      ..value = 'captain'
      ..removeFails = true
      ..throws = true;
    final c = s.owner();
    addTearDown(c.current.dispose);
    await c.load();
    CharacterStore.debugOverride = c;
    await expectLater(
      registryClear(),
      throwsA(
        isA<CharacterStorageException>().having(
          (e) => e.toString(),
          'safe',
          isNot(contains('private')),
        ),
      ),
    );
    expect(c.current.value.id, 'captain');
    s.removeFails = false;
    await registryClear();
    expect(s.value, null);
    expect(c.current.value.id, 'bluey');
  });
  test('entered write then registry clear leaves default with no stale Captain publication', () async {
    final s = Storage(), c = s.owner();
    addTearDown(c.current.dispose);
    CharacterStore.debugOverride = c;
    final e = Completer<void>(), r = Completer<void>();
    s.writeEntered = e;
    s.writeRelease = r;
    final seen = <String>[];
    c.current.addListener(() => seen.add(c.current.value.id));
    final write = c.select('captain');
    await e.future;
    final clear = registryClear();
    r.complete();
    await Future.wait([write, clear]);
    expect(s.value, null);
    expect(c.current.value.id, 'bluey');
    expect(seen, isEmpty);
  });
  test('failed write may change actual storage; reconciliation does not imply rollback', () async {
    String? stored = 'captain';
    var fail = true;
    final c = CharacterStore(
      read: () async => stored,
      write: (id) async {
        stored = id;
        if (fail) throw StateError('private');
        return true;
      },
      remove: () async {
        stored = null;
        return true;
      },
    );
    addTearDown(c.current.dispose);
    await c.load();
    await expectLater(
      c.select('bluey'),
      throwsA(isA<CharacterStorageException>()),
    );
    expect(stored, 'bluey');
    expect(c.current.value.id, 'bluey');
    expect(c.verified, true);
    fail = false;
    await c.select('captain');
    expect(c.current.value.id, 'captain');
  });
  test('failed post-write read then successful reconciliation publishes actual but still reports failure', () async {
    String? stored = 'captain';
    var reads = 0;
    final c = CharacterStore(
      read: () async {
        if (reads++ == 1) throw StateError('private');
        return stored;
      },
      write: (id) async {
        stored = id;
        return true;
      },
      remove: () async {
        stored = null;
        return true;
      },
    );
    addTearDown(c.current.dispose);
    await c.load();
    await expectLater(
      c.select('bluey'),
      throwsA(isA<CharacterStorageException>()),
    );
    expect(c.current.value.id, 'bluey');
    expect(c.verified, true);
    await c.load();
  });
  test('unknown persisted ID remains unchanged with Bluey fallback', () async {
    final s = Storage(), c = s.owner();
    addTearDown(c.current.dispose);
    await c.select('nobody');
    expect(s.value, 'nobody');
    expect(c.current.value.id, 'bluey');
    await c.load();
    expect(c.verified, true);
  });
  test('caller audit preserves excluded awaited main startup wiring', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('await CharacterStore.instance.load();'));
  });
}
