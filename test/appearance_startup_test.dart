import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/ui/theme.dart';
import 'package:local_bluey/services/appearance_startup.dart';

void main() {
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
      'Strings.load()',
      'EgressMonitor.instance.load()',
      'ActionLog.instance.load()',
      'RoutineStore.instance.load()',
      'BiometricLock.instance.load()',
    ]) {
      expect(startup, contains('await $load;'));
    }
    expect(startup, contains('await character.reload();'));
    expect(startup, contains('await windowManager.ensureInitialized();'));
    expect(s, contains('themeMode: ThemeController.instance.mode'));
  });
}
