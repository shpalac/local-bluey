import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/ui/theme.dart';
import 'package:local_bluey/services/appearance_startup.dart';

void main() {
  test(
    'immediate scheduled disposal performs no mutation notification or entry',
    () async {
      var reads = 0, notices = 0;
      final c = AppearanceStartup(
        reload: () async {
          reads++;
        },
      );
      c.addListener(() => notices++);
      final work = c.reload();
      c.dispose();
      c.dispose();
      await work;
      expect(c.loading, false);
      expect(c.failed, false);
      expect(notices, 0);
      expect(reads, 0);
      await c.retry();
      await c.reload();
      expect(reads, 0);
    },
  );
  for (final fail in [false, true]) {
    for (final disposeEntered in [false, true]) {
      test(
        'queued latest actual read fail=$fail disposed=$disposeEntered joins and settles',
        () async {
          var reads = 0, notices = 0, held = false;
          final entered = Completer<void>(), release = Completer<void>();
          Future<String?> read() async {
            reads++;
            if (held) {
              if (!entered.isCompleted) entered.complete();
              await release.future;
              if (fail) throw StateError('private');
            }
            return 'dark';
          }

          final owner = ThemeController.forTest(
            read: read,
            write: (_) async => true,
            remove: () async => true,
          );
          await owner.load();
          final c = AppearanceStartup(reload: owner.load);
          c.addListener(() => notices++);
          held = true;
          final beforeReads = reads;
          final obsolete = c.reload(), latest = c.reload(), retry = c.retry();
          expect(retry, same(latest));
          await entered.future;
          expect(notices, 1);
          expect(reads, beforeReads + 1);
          expect(c.loading, true);
          var settled = false;
          retry.then((_) => settled = true);
          await Future<void>.value();
          expect(settled, false);
          if (disposeEntered) c.dispose();
          final beforeNotices = notices;
          release.complete();
          await Future.wait([obsolete, latest, retry]);
          expect(settled, true);
          if (disposeEntered) {
            expect(notices, beforeNotices);
            expect(c.failed, false);
          } else {
            expect(c.loading, false);
            expect(c.failed, fail);
            expect(notices, 2);
          }
          expect(owner.mode, ThemeMode.dark);
          c.dispose();
          owner.dispose();
        },
      );
    }
  }

  for (final mode in ['light', 'dark', null]) {
    test(
      'actual theme failed read preserves $mode mode until fresh explicit retry',
      () async {
        var stored = mode, fail = false, reads = 0;
        final theme = ThemeController.forTest(
          read: () async {
            reads++;
            if (fail) throw StateError('private');
            return stored;
          },
          write: (_) async => true,
          remove: () async => true,
        );
        await theme.load();
        final retained = theme.mode;
        final c = AppearanceStartup(reload: theme.load);
        fail = true;
        await c.reload();
        expect(c.failed, true);
        expect(theme.mode, retained);
        final before = reads;
        fail = false;
        stored = 'dark';
        await c.retry();
        expect(reads, greaterThan(before));
        expect(c.failed, false);
        expect(theme.mode, ThemeMode.dark);
        c.dispose();
        theme.dispose();
      },
    );
  }
  test(
    'actual failed entered read reconciles but caller still reports failure',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var reads = 0;
      final theme = ThemeController.forTest(
        read: () async {
          reads++;
          if (reads == 1) {
            entered.complete();
            await release.future;
            throw StateError('private');
          }
          return 'light';
        },
        write: (_) async => true,
        remove: () async => true,
      );
      final c = AppearanceStartup(reload: theme.load);
      final op = c.reload();
      await entered.future;
      expect(c.loading, true);
      final retry = c.retry();
      expect(identical(op, retry), true);
      expect(reads, 1); // No automatic or duplicate read while entered.
      release.complete();
      await op;
      expect(c.failed, true);
      expect(theme.mode, ThemeMode.light);
      expect(reads, 2);
      await c.retry();
      expect(reads, 3);
      expect(c.failed, false);
      c.dispose();
      theme.dispose();
    },
  );
  test('actual ordered old read failure cannot replace newer successful load status', () async {
    final entered = Completer<void>(), release = Completer<void>();
    var reads = 0;
    final theme = ThemeController.forTest(
      read: () async {
        reads++;
        if (reads == 1) {
          entered.complete();
          await release.future;
          throw StateError('private');
        }
        return 'dark';
      },
      write: (_) async => true,
      remove: () async => true,
    );
    final c = AppearanceStartup(reload: theme.load);
    final old = c.reload();
    await entered.future;
    final fresh = c.reload();
    release.complete();
    await Future.wait([old, fresh]);
    expect(theme.mode, ThemeMode.dark);
    expect(c.failed, false);
    c.dispose();
    theme.dispose();
  });
  test(
    'actual entered theme load after caller disposal cannot publish notice',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final theme = ThemeController.forTest(
        read: () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          throw StateError('private');
        },
        write: (_) async => true,
        remove: () async => true,
      );
      final c = AppearanceStartup(reload: theme.load);
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
      theme.dispose();
    },
  );
  for (final sync in [false, true]) {
    test('sync throw=$sync safely contained without raw details', () async {
      final c = AppearanceStartup(
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
      final theme = ThemeController.forTest(
        read: () async {
          reads++;
          await gate.future;
          return 'dark';
        },
        write: (_) async => true,
        remove: () async => true,
      );
      final c = AppearanceStartup(reload: theme.load);
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
      theme.dispose();
    },
  );
  test('reentrant caller disposal prevents not-yet-entered load', () async {
    var reads = 0;
    final c = AppearanceStartup(
      reload: () async {
        reads++;
      },
    );
    c.addListener(c.dispose);
    await c.reload();
    expect(reads, 0);
  });
  test('actual main appearance-only startup/source wiring and preceding loads unchanged', () {
    final s = File('lib/main.dart').readAsStringSync();
    expect(s, contains('final appearance = AppearanceStartup();'));
    expect(s, contains('await appearance.reload();'));
    expect(s, contains('appearance: appearance'));
    final startup = s.substring(
      s.indexOf('void main() async'),
      s.indexOf('/// Picks the home'),
    );
    for (final load in [
      'EgressMonitor.instance.load()',
      'ActionLog.instance.load()',
      'RoutineStore.instance.load()',
      'BiometricLock.instance.load()',
    ]) {
      expect(startup, contains('await $load;'));
    }
    expect(startup, contains('await language.reload();'));
    expect(startup, contains('await character.reload();'));
    expect(startup, contains('await windowManager.ensureInitialized();'));
    expect(s, contains('themeMode: ThemeController.instance.mode'));
  });
}
