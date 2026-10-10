import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/hold_key_caller.dart';
import 'package:local_bluey/services/hold_key_controller.dart';

import 'hold_key_lifecycle_test.dart' show Fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final stage in ['permission', 'request', 'enable', 'disable']) {
    test(
      'actual controller entered $stage failure, safe caller fresh-load retry',
      () async {
        final f = Fixture();
        await f.settings.setEnabled(true);
        f.configure = (b) {
          b.hold = stage;
          b.fail = stage;
          if (stage == 'request') b.allowed = false;
        };
        final c = HoldKeyCaller(settings: f.settings, controller: f.controller);
        if (stage == 'disable') {
          f.configure = null;
          await c.loadAndSync();
          final b = f.bridges.single;
          b.hold = stage;
          b.fail = stage;
          await f.settings.setEnabled(false);
        }
        final op = stage == 'disable' ? c.sync() : c.loadAndSync();
        await Future<void>.delayed(Duration.zero);
        final b = f.bridges.single;
        await b.entered.future;
        expect(c.loading, true);
        b.release.complete();
        await op;
        expect(c.failed, true);
        for (final b in f.bridges) {
          b.fail = null;
        }
        f.configure = null;
        final a = c.retry();
        final other = c.retry();
        expect(identical(a, other), true);
        await a;
        expect(c.failed, false);
        expect(f.settings.verified, true);
        await c.close();
        c.dispose();
      },
    );
  }

  for (final closing in [false, true]) {
    test('actual entered preference read failure closing=$closing', () async {
      final entered = Completer<void>(), release = Completer<void>();
      var fail = true, reads = 0, gate = true;
      final settings = HoldKeySettings(
        read: (key) async {
          reads++;
          if (gate) {
            gate = false;
            entered.complete();
            await release.future;
          }
          if (fail) throw StateError('private persisted detail');
          return null;
        },
      );
      final controller = HoldKeyController(
        settings: settings,
        onStart: () async {},
        onSend: () async {},
        onCancel: () async {},
      );
      final c = HoldKeyCaller(settings: settings, controller: controller);
      final op = c.loadAndSync();
      await entered.future;
      expect(identical(op, c.retry()), true);
      if (closing) {
        await c.close();
        c.dispose();
      }
      release.complete();
      await op;
      if (!closing) {
        expect(c.failed, true);
        final before = reads;
        fail = false;
        await c.retry();
        expect(reads, greaterThan(before));
        expect(c.failed, false);
        await c.close();
        c.dispose();
      }
      expect(controller.running, false);
    });
  }

  test('actual load-following entered enable invalidated by fresh OFF listener sync', () async {
    final f = Fixture();
    await f.settings.setEnabled(true);
    f.configure = (b) {
      b.hold = 'enable';
    };
    final c = HoldKeyCaller(settings: f.settings, controller: f.controller);
    f.settings.addListener(() {
      unawaited(c.sync());
    });
    final op = c.loadAndSync();
    await Future<void>.delayed(Duration.zero);
    final b = f.bridges.single;
    await b.entered.future;
    await f.settings.setEnabled(false);
    final fresh = c.sync();
    b.release.complete();
    await op;
    await fresh;
    expect(f.controller.running, false);
    expect(b.disables, 1);
    expect(c.failed, false);
    await c.close();
    c.dispose();
  });

  test(
    'reentrant loading listener close prevents not-yet-entered effects',
    () async {
      var loads = 0, syncs = 0;
      final c = HoldKeyCaller.operations(
        load: () async {
          loads++;
        },
        sync: () async {
          syncs++;
        },
        close: () async {},
      );
      c.addListener(() {
        unawaited(c.close());
      });
      await c.loadAndSync();
      expect(loads, 0);
      expect(syncs, 0);
      c.dispose();
    },
  );

  test(
    'actual load failure retains snapshot no sync on fresh-load retry failure',
    () async {
      var fail = false, reads = 0;
      final settings = HoldKeySettings(
        read: (key) async {
          reads++;
          if (fail) throw StateError('private');
          return key == 'holdkey.enabled' ? true : null;
        },
      );
      final f = Fixture();
      final controller = HoldKeyController(
        settings: settings,
        onStart: () async {},
        onSend: () async {},
        onCancel: () async {},
        createBridge: (m, a) => throw StateError('unexpected bridge'),
      );
      final c = HoldKeyCaller(settings: settings, controller: controller);
      await settings.load();
      fail = true;
      await c.loadAndSync();
      expect(c.failed, true);
      expect(settings.enabled, true);
      expect(settings.verified, false);
      final before = reads;
      await c.retry();
      expect(reads, greaterThan(before));
      expect(c.failed, true);
      await c.close();
      c.dispose();
      expect(f.bridges, isEmpty);
    },
  );

  test('load listener suppressed until verified load then one sync', () async {
    final f = Fixture();
    await f.settings.setEnabled(true);
    final c = HoldKeyCaller(settings: f.settings, controller: f.controller);
    f.settings.addListener(() {
      unawaited(c.sync());
    });
    await c.loadAndSync();
    expect(f.bridges.length, 1);
    expect(f.bridges.single.enables, 1);
    await c.retry();
    expect(f.bridges.length, 1);
    await c.close();
    c.dispose();
  });

  for (final throwsSync in [false, true]) {
    for (final action in ['load', 'sync', 'close']) {
      test('$action syncThrow=$throwsSync contained zero uncaught', () async {
        Future<void> failure() {
          if (throwsSync) throw StateError('private');
          return Future.error(StateError('private'));
        }

        final c = HoldKeyCaller.operations(
          load: action == 'load' ? failure : () async {},
          sync: action == 'sync' ? failure : () async {},
          close: action == 'close' ? failure : () async {},
        );
        if (action == 'close') {
          await c.close();
          expect(c.closeFailed, true);
        } else {
          await c.loadAndSync();
          expect(c.failed, true);
        }
        c.dispose();
      });
    }
  }

  test(
    'old completion/error never overrides newer invocation or disposed state',
    () async {
      final gates = <Completer<void>>[];
      final c = HoldKeyCaller.operations(
        load: () async {},
        sync: () {
          final g = Completer<void>();
          gates.add(g);
          return g.future;
        },
        close: () async {},
      );
      var notices = 0;
      c.addListener(() {
        notices++;
      });
      final old = c.sync();
      final fresh = c.sync();
      gates[1].completeError(StateError('private newer'));
      await fresh;
      expect(c.failed, true);
      gates[0].complete();
      await old;
      expect(c.failed, true);
      final late = c.sync();
      await c.close();
      c.dispose();
      final before = notices;
      gates[2].completeError(StateError('private disposed'));
      await late;
      expect(notices, before);
    },
  );

  test('actual close entered disable failure after unmount is retained and explicit retryable', () async {
    final f = Fixture();
    await f.settings.setEnabled(true);
    final c = HoldKeyCaller(settings: f.settings, controller: f.controller);
    await c.loadAndSync();
    final b = f.bridges.single;
    b.hold = 'disable';
    b.disableFails = true;
    var notices = 0;
    c.addListener(() {
      notices++;
    });
    final op = c.close();
    final same = c.close();
    expect(identical(op, same), true);
    await b.entered.future;
    c.dispose();
    final before = notices;
    b.release.complete();
    await op;
    expect(c.closeFailed, true);
    expect(f.controller.cleanupPending, true);
    expect(notices, before);
    b.disableFails = false;
    await c.close();
    expect(c.closeFailed, false);
    expect(f.controller.cleanupPending, false);
  });

  test('actual main source wiring only, preserves owner implementations', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('unawaited(_holdKeyCaller.loadAndSync())'));
    expect(source, contains('unawaited(_holdKeyCaller.sync())'));
    expect(source, contains('unawaited(_holdKeyCaller.close())'));
    expect(source, isNot(contains('HoldKeySettings.instance.load().then')));
    expect(
      'HoldKeyCallerNotice(caller: _holdKeyCaller)'.allMatches(source).length,
      2,
    );
  });
}
