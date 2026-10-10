import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/characters.dart';
import 'package:local_bluey/services/character_startup.dart';

void main() {
  for (final choice in ['bluey', 'captain', null]) {
    test(
      'actual character failed read preserves $choice choice until fresh explicit retry',
      () async {
        var stored = choice, fail = false, reads = 0;
        final store = CharacterStore(
          read: () async {
            reads++;
            if (fail) throw StateError('private');
            return stored;
          },
          write: (_) async => true,
          remove: () async => true,
        );
        await store.load();
        final retained = store.current.value;
        final c = CharacterStartup(
          reload: store.load,
          verified: () => store.verified,
        );
        fail = true;
        await c.reload();
        expect(c.failed, true);
        expect(store.current.value, same(retained));
        expect(store.verified, false);
        expect(c.verified, false);
        final before = reads;
        fail = false;
        stored = 'captain';
        await c.retry();
        expect(reads, greaterThan(before));
        expect(c.failed, false);
        expect(c.verified, true);
        expect(store.current.value, BlueyCharacters.captain);
        c.dispose();
        store.current.dispose();
      },
    );
  }
  test(
    'actual failed entered read reconciles but caller still reports failure',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var reads = 0;
      final store = CharacterStore(
        read: () async {
          reads++;
          if (reads == 1) {
            entered.complete();
            await release.future;
            throw StateError('private');
          }
          return 'bluey';
        },
        write: (_) async => true,
        remove: () async => true,
      );
      final c = CharacterStartup(
        reload: store.load,
        verified: () => store.verified,
      );
      final op = c.reload();
      await entered.future;
      expect(c.loading, true);
      final retry = c.retry();
      expect(identical(op, retry), true);
      expect(reads, 1); // No automatic or duplicate read while entered.
      release.complete();
      await op;
      expect(c.failed, true);
      expect(store.current.value, BlueyCharacters.bluey);
      expect(reads, 2);
      expect(c.verified, true);
      await c.retry();
      expect(reads, 3);
      expect(c.failed, false);
      c.dispose();
      store.current.dispose();
    },
  );
  test('actual ordered old read failure cannot replace newer successful load status', () async {
    final entered = Completer<void>(), release = Completer<void>();
    var reads = 0;
    final store = CharacterStore(
      read: () async {
        reads++;
        if (reads == 1) {
          entered.complete();
          await release.future;
          throw StateError('private');
        }
        return 'captain';
      },
      write: (_) async => true,
      remove: () async => true,
    );
    final c = CharacterStartup(
      reload: store.load,
      verified: () => store.verified,
    );
    final old = c.reload();
    await entered.future;
    final fresh = c.reload();
    release.complete();
    await Future.wait([old, fresh]);
    expect(store.current.value, BlueyCharacters.captain);
    expect(c.failed, false);
    c.dispose();
    store.current.dispose();
  });
  test(
    'actual entered character load after caller disposal cannot publish notice',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final store = CharacterStore(
        read: () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          throw StateError('private');
        },
        write: (_) async => true,
        remove: () async => true,
      );
      final c = CharacterStartup(
        reload: store.load,
        verified: () => store.verified,
      );
      var notices = 0;
      c.addListener(() {
        notices++;
      });
      final op = c.reload();
      await entered.future;
      c.dispose();
      final before = notices;
      release.complete();
      await op;
      expect(notices, before);
      store.current.dispose();
    },
  );
  for (final sync in [false, true]) {
    test('sync throw=$sync safely contained without raw details', () async {
      final c = CharacterStartup(
        reload: () {
          if (sync) throw StateError('private');
          return Future.error(StateError('private'));
        },
      );
      await c.reload();
      expect(c.failed, true);
      c.dispose();
    });
  }
  test(
    'reentrant loading retry joins installed owner with one actual read',
    () async {
      var reads = 0;
      final gate = Completer<void>();
      final store = CharacterStore(
        read: () async {
          reads++;
          await gate.future;
          return 'captain';
        },
        write: (_) async => true,
        remove: () async => true,
      );
      final c = CharacterStartup(
        reload: store.load,
        verified: () => store.verified,
      );
      Future<void>? joined;
      c.addListener(() {
        if (c.loading) joined = c.retry();
      });
      final op = c.reload();
      await Future<void>.delayed(Duration.zero);
      expect(identical(op, joined), true);
      expect(reads, 1);
      gate.complete();
      await op;
      expect(reads, 1);
      c.dispose();
      store.current.dispose();
    },
  );
  test('reentrant caller disposal prevents not-yet-entered load', () async {
    var reads = 0;
    final c = CharacterStartup(
      reload: () async {
        reads++;
      },
    );
    c.addListener(c.dispose);
    await c.reload();
    expect(reads, 0);
  });
  test('successful caller is not independent choice verification', () async {
    final c = CharacterStartup(reload: () async {}, verified: () => false);
    await c.reload();
    expect(c.failed, false);
    expect(c.verified, false);
    c.dispose();
    await c.retry();
  });

  test('actual main only character load is contained', () {
    final s = File('lib/main.dart').readAsStringSync();
    expect(s, contains('final character = CharacterStartup();'));
    expect(s, contains('await character.reload();'));
    expect(s, contains('character: character'));
    final startup = s.substring(
      s.indexOf('void main() async'),
      s.indexOf('/// Picks the home'),
    );
    for (final load in [
      'Strings.load()',
      'EgressMonitor.instance.load()',
      'ActionLog.instance.load()',
      'RoutineStore.instance.load()',
      'BiometricLock.instance.load()',
      'windowManager.ensureInitialized()',
    ]) {
      expect(startup, contains('await $load;'));
    }
    expect(startup, contains('await appearance.reload();'));
    expect(
      startup.indexOf('await character.reload();'),
      lessThan(startup.indexOf('await BiometricLock.instance.load();')),
    );
  });
}
