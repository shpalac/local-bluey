import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/haptics.dart';

void main() {
  for (final stage in ['read', 'write', 'remove']) {
    test(
      'entered $stage before clear/new choice cannot restore flag',
      () async {
        bool? stored = false;
        final entered = Completer<void>(), release = Completer<void>();
        var hold = true;
        Future<void> pause(String operation) async {
          if (hold && operation == stage) {
            hold = false;
            entered.complete();
            await release.future;
          }
        }

        final controller = RemoteHaptics.forTest(
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
            ? controller.setEnabled(false)
            : controller.clear();
        await entered.future;
        final clear = controller.clear();
        final choice = controller.setEnabled(false);
        release.complete();
        await Future.wait([old, clear, choice]);
        expect(stored, false);
        expect(controller.enabled, false);
        controller.dispose();
      },
    );
  }
  for (final operation in ['write', 'remove']) {
    for (final throws in [false, true]) {
      test(
        '$operation ${throws ? 'throw' : 'false'} reports safely and retries',
        () async {
          bool? stored = false;
          var fail = true;
          final controller = RemoteHaptics.forTest(
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
                ? controller.setEnabled(false)
                : controller.clear(),
            throwsA(
              isA<HapticsStorageException>().having(
                (e) => e.toString(),
                'safe',
                isNot(contains('private sentinel')),
              ),
            ),
          );
          expect(stored, false);
          expect(controller.enabled, false);
          fail = false;
          await controller.clear();
          expect(stored, isNull);
          expect(controller.enabled, true);
          await controller.setEnabled(false);
          expect(stored, false);
          expect(controller.enabled, false);
          controller.dispose();
        },
      );
    }
  }
  test(
    'entered write then clear removes preference before completing',
    () async {
      bool? stored;
      final entered = Completer<void>(), release = Completer<void>();
      final c = RemoteHaptics.forTest(
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
      final old = c.setEnabled(false);
      await entered.future;
      final clear = c.clear();
      release.complete();
      await Future.wait([old, clear]);
      expect(stored, isNull);
      expect(c.enabled, true);
      c.dispose();
    },
  );
  test(
    'failed clear after entered write reconciles retained preference',
    () async {
      bool? stored;
      final entered = Completer<void>(), release = Completer<void>();
      var fail = true;
      final c = RemoteHaptics.forTest(
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
      final old = c.setEnabled(false);
      await entered.future;
      final clear = c.clear();
      final expected = expectLater(
        clear,
        throwsA(isA<HapticsStorageException>()),
      );
      release.complete();
      await old;
      await expected;
      expect(stored, false);
      expect(c.enabled, false);
      fail = false;
      await c.clear();
      expect(stored, isNull);
      expect(c.enabled, true);
      c.dispose();
    },
  );

  test(
    'old entered read followed by clear publishes only default-on',
    () async {
      bool? stored = false;
      final entered = Completer<void>(), release = Completer<void>();
      final seen = <bool>[];
      final c = RemoteHaptics.forTest(
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
      c.addListener(() => seen.add(c.enabled));
      final old = c.load();
      await entered.future;
      final clear = c.clear();
      release.complete();
      await Future.wait([old, clear]);
      expect(seen, [true]);
      expect(stored, isNull);
      c.dispose();
    },
  );
  test(
    'clear resumes counting once per event, fresh off suppresses all',
    () async {
      bool? stored = false;
      final c = RemoteHaptics.forTest(
        read: () async => stored,
        write: (value) async {
          stored = value;
          return true;
        },
        remove: () async {
          stored = null;
          return true;
        },
      );
      final fake = Counting();
      c.debugImpl = fake;
      await c.load();
      for (final event in RemoteHapticEvent.values) {
        await c.fire(event);
      }
      expect(fake.count, 0);
      await c.clear();
      for (final event in RemoteHapticEvent.values) {
        await c.fire(event);
      }
      expect(fake.count, RemoteHapticEvent.values.length);
      await c.setEnabled(false);
      for (final event in RemoteHapticEvent.values) {
        await c.fire(event);
      }
      expect(fake.count, RemoteHapticEvent.values.length);
      c.dispose();
    },
  );
}

class Counting implements Haptics {
  int count = 0;
  @override
  Future<void> light() async {
    count++;
  }

  @override
  Future<void> medium() async {
    count++;
  }

  @override
  Future<void> error() async {
    count++;
  }
}
