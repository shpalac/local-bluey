import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/ui/theme.dart';

void main() {
  for (final stage in ['read', 'write', 'remove']) {
    test(
      'entered $stage before clear/new choice cannot restore override',
      () async {
        String? stored = 'dark';
        final entered = Completer<void>(), release = Completer<void>();
        var hold = true;
        Future<void> pause(String operation) async {
          if (hold && operation == stage) {
            hold = false;
            entered.complete();
            await release.future;
          }
        }

        final controller = ThemeController.forTest(
          read: () async {
            final result = stored;
            await pause('read');
            return result;
          },
          write: (value) async {
            await pause('write');
            stored = value;
            return true;
          },
          remove: () async {
            await pause('remove');
            stored = null;
            return true;
          },
        );
        final old = stage == 'read'
            ? controller.load()
            : stage == 'write'
            ? controller.setMode(ThemeMode.dark)
            : controller.clear();
        await entered.future;
        final clear = controller.clear();
        final choice = controller.setMode(ThemeMode.light);
        release.complete();
        await Future.wait([old, clear, choice]);
        expect(stored, 'light');
        expect(controller.mode, ThemeMode.light);
        controller.dispose();
      },
    );
  }
  for (final operation in ['write', 'remove']) {
    for (final throws in [false, true]) {
      test(
        '$operation ${throws ? 'throw' : 'false'} reports safely and retries',
        () async {
          String? stored = 'dark';
          var fail = true;
          final controller = ThemeController.forTest(
            read: () async => stored,
            write: (value) async {
              if (operation == 'write' && fail) {
                if (throws) throw StateError('private sentinel');
                return false;
              }
              stored = value;
              return true;
            },
            remove: () async {
              if (operation == 'remove' && fail) {
                if (throws) throw StateError('private sentinel');
                return false;
              }
              stored = null;
              return true;
            },
          );
          await controller.load();
          await expectLater(
            operation == 'write'
                ? controller.setMode(ThemeMode.light)
                : controller.clear(),
            throwsA(
              isA<ThemeStorageException>().having(
                (e) => e.toString(),
                'safe',
                isNot(contains('private sentinel')),
              ),
            ),
          );
          expect(stored, 'dark');
          expect(controller.mode, ThemeMode.dark);
          fail = false;
          await controller.clear();
          expect(stored, isNull);
          expect(controller.mode, ThemeMode.system);
          await controller.setMode(ThemeMode.light);
          expect(stored, 'light');
          expect(controller.mode, ThemeMode.light);
          controller.dispose();
        },
      );
    }
  }
  test(
    'entered write then clear removes preference before completing',
    () async {
      String? stored;
      final entered = Completer<void>(), release = Completer<void>();
      final c = ThemeController.forTest(
        read: () async => stored,
        write: (value) async {
          entered.complete();
          await release.future;
          stored = value;
          return true;
        },
        remove: () async {
          stored = null;
          return true;
        },
      );
      final old = c.setMode(ThemeMode.dark);
      await entered.future;
      final clear = c.clear();
      release.complete();
      await Future.wait([old, clear]);
      expect(stored, isNull);
      expect(c.mode, ThemeMode.system);
      c.dispose();
    },
  );
  test(
    'failed clear after entered write reconciles retained preference',
    () async {
      String? stored;
      final entered = Completer<void>(), release = Completer<void>();
      var fail = true;
      final c = ThemeController.forTest(
        read: () async => stored,
        write: (value) async {
          entered.complete();
          await release.future;
          stored = value;
          return true;
        },
        remove: () async {
          if (fail) return false;
          stored = null;
          return true;
        },
      );
      final old = c.setMode(ThemeMode.dark);
      await entered.future;
      final clear = c.clear();
      final expected = expectLater(
        clear,
        throwsA(isA<ThemeStorageException>()),
      );
      release.complete();
      await old;
      await expected;
      expect(stored, 'dark');
      expect(c.mode, ThemeMode.dark);
      fail = false;
      await c.clear();
      expect(stored, isNull);
      expect(c.mode, ThemeMode.system);
      c.dispose();
    },
  );

  test('old entered read followed by clear publishes only System', () async {
    String? stored = 'dark';
    final entered = Completer<void>(), release = Completer<void>();
    final seen = <ThemeMode>[];
    final c = ThemeController.forTest(
      read: () async {
        final value = stored;
        entered.complete();
        await release.future;
        return value;
      },
      write: (value) async {
        stored = value;
        return true;
      },
      remove: () async {
        stored = null;
        return true;
      },
    );
    c.addListener(() => seen.add(c.mode));
    final old = c.load();
    await entered.future;
    final clear = c.clear();
    release.complete();
    await Future.wait([old, clear]);
    expect(seen, [ThemeMode.system]);
    expect(stored, isNull);
    c.dispose();
  });
}
