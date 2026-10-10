import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/hold_key.dart';
import 'package:local_bluey/services/hold_key_bridge.dart';
import 'package:local_bluey/services/hold_key_controller.dart';
import 'package:local_bluey/services/data_registry.dart';

class Bridge extends HoldKeyBridge {
  Bridge(HoldKeyMachine machine, void Function(HoldKeyAction) onAction)
    : super(machine: machine, onAction: onAction);
  bool on = false, allowed = true, enableResult = true, disableFails = false;
  String? hold, fail;
  final entered = Completer<void>(), release = Completer<void>();
  int enables = 0, disables = 0, requests = 0, resets = 0;
  void Function()? reenter;
  Future<void> stage(String name) async {
    if (hold == name) {
      hold = null;
      entered.complete();
      await release.future;
    }
    if (fail == name) throw StateError('private bridge');
  }

  @override
  bool get enabled => on;
  @override
  Future<bool> hasPermission() async {
    await stage('permission');
    return allowed;
  }

  @override
  Future<bool> requestPermission() async {
    requests++;
    await stage('request');
    return allowed;
  }

  @override
  Future<bool> enable() async {
    enables++;
    reenter?.call();
    await stage('enable');
    on = enableResult;
    return on;
  }

  @override
  Future<void> disable() async {
    disables++;
    await stage('disable');
    if (disableFails) throw StateError('private stop');
    on = false;
    emit(HoldKeyAction.cancel);
  }

  @override
  void reset() {
    resets++;
    emit(HoldKeyAction.cancel);
  }

  void emit(HoldKeyAction a) => onAction(a);
}

class Fixture {
  final data = <String, Object>{};
  final bridges = <Bridge>[], log = <String>[];
  late final settings = HoldKeySettings(
    read: (k) async => data[k],
    write: (k, v) async {
      data[k] = v;
      return true;
    },
    remove: (k) async {
      data.remove(k);
      return true;
    },
  );
  late final controller = HoldKeyController(
    settings: settings,
    onStart: () async {
      log.add('start');
    },
    onSend: () async {
      log.add('send');
    },
    onCancel: () async {
      log.add('cancel');
    },
    createBridge: (m, a) {
      final b = Bridge(m, a);
      configure?.call(b);
      bridges.add(b);
      return b;
    },
  );
  void Function(Bridge)? configure;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => HoldKeySettings.debugOverride = null);
  for (final stage in ['permission', 'request', 'enable']) {
    for (final change in ['off', 'clear', 'key', 'threshold', 'dispose']) {
      test(
        'entered $stage versus $change never revives old candidate',
        () async {
          final f = Fixture();
          addTearDown(f.settings.dispose);
          await f.settings.setEnabled(true);
          f.configure = (b) {
            if (f.bridges.isEmpty) {
              b.hold = stage;
              b.allowed = stage != 'request';
            }
          };
          final first = f.controller.sync();
          while (f.bridges.isEmpty) {
            await Future<void>.delayed(Duration.zero);
          }
          final old = f.bridges.single;
          await old.entered.future;
          Future<void> next;
          switch (change) {
            case 'off':
              await f.settings.setEnabled(false);
              next = f.controller.sync();
            case 'clear':
              HoldKeySettings.debugOverride = f.settings;
              await DataRegistry.stores
                  .firstWhere((s) => s.id == 'hold_key_pref')
                  .clear();
              next = f.controller.sync();
            case 'key':
              await f.settings.setKey(HoldKey.fn);
              next = f.controller.sync();
            case 'threshold':
              await f.settings.setThresholdMs(600);
              next = f.controller.sync();
            default:
              next = f.controller.dispose();
          }
          var stopped = false;
          next.then((_) => stopped = true);
          await Future<void>.delayed(Duration.zero);
          expect(stopped, false);
          old.emit(HoldKeyAction.start);
          old.emit(HoldKeyAction.send);
          expect(f.log, isEmpty);
          old.release.complete();
          await Future.wait([first, next]);
          expect(old.on, false);
          expect(old.disables, 1);
          if (change == 'key' || change == 'threshold') {
            expect(f.bridges.length, 2);
            expect(f.controller.running, true);
            expect(
              f.bridges.last.machine.key,
              change == 'key' ? HoldKey.fn : HoldKey.rightCommand,
            );
            expect(
              f.bridges.last.machine.threshold.inMilliseconds,
              change == 'threshold' ? 600 : 400,
            );
          } else {
            expect(f.controller.running, false);
            expect(f.bridges.length, 1);
          }
          old.emit(HoldKeyAction.start);
          old.emit(HoldKeyAction.send);
          expect(f.log, isEmpty);
          await f.controller.dispose();
          await f.controller.sync();
          expect(f.controller.running, false);
        },
      );
    }
  }
  test(
    'equal concurrent and enable reentrant sync coalesce one candidate',
    () async {
      final f = Fixture();
      addTearDown(f.settings.dispose);
      await f.settings.setEnabled(true);
      Future<void>? nested;
      f.configure = (b) {
        b.hold = 'enable';
        b.reenter = () {
          nested = f.controller.sync();
        };
      };
      final first = f.controller.sync(), second = f.controller.sync();
      expect(identical(first, second), true);
      while (f.bridges.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await f.bridges.single.entered.future;
      expect(f.bridges.length, 1);
      f.bridges.single.release.complete();
      await Future.wait([first, second, nested!]);
      expect(f.bridges.single.enables, 1);
      await f.controller.dispose();
    },
  );
  test(
    'callback current routing reset and superseded cancellation exactly once',
    () async {
      final f = Fixture();
      addTearDown(f.settings.dispose);
      await f.settings.setEnabled(true);
      await f.controller.sync();
      final old = f.bridges.single;
      old.emit(HoldKeyAction.start);
      old.emit(HoldKeyAction.send);
      old.emit(HoldKeyAction.cancel);
      expect(f.log, ['start', 'send', 'cancel']);
      old.emit(HoldKeyAction.start);
      f.controller.reset();
      expect(f.log.last, 'cancel');
      old.emit(HoldKeyAction.start);
      await f.settings.setKey(HoldKey.fn);
      final work = f.controller.sync();
      old.emit(HoldKeyAction.send);
      await work;
      expect(f.log, [
        'start',
        'send',
        'cancel',
        'start',
        'cancel',
        'start',
        'cancel',
      ]);
      old.emit(HoldKeyAction.start);
      old.emit(HoldKeyAction.send);
      old.emit(HoldKeyAction.cancel);
      expect(f.log.length, 7);
      await f.controller.dispose();
    },
  );
  for (final stage in ['permission', 'request', 'enable']) {
    test(
      '$stage failure cleanup retained safe exception explicit retry',
      () async {
        final f = Fixture();
        addTearDown(f.settings.dispose);
        await f.settings.setEnabled(true);
        f.configure = (b) {
          if (f.bridges.isEmpty) {
            b.fail = stage;
            b.allowed = stage != 'request';
          }
        };
        await expectLater(
          f.controller.sync(),
          throwsA(
            isA<HoldKeyControllerException>().having(
              (e) => e.toString(),
              'safe',
              isNot(contains('private')),
            ),
          ),
        );
        expect(f.bridges.single.disables, 1);
        expect(f.controller.running, false);
        await f.controller.sync();
        expect(f.controller.running, true);
        await f.controller.dispose();
      },
    );
  }
  test(
    'failed disable retains exact bridge and uncertainty until explicit retry',
    () async {
      final f = Fixture();
      addTearDown(f.settings.dispose);
      await f.settings.setEnabled(true);
      await f.controller.sync();
      final old = f.bridges.single;
      old.emit(HoldKeyAction.start);
      old.disableFails = true;
      await f.settings.setEnabled(false);
      await expectLater(
        f.controller.sync(),
        throwsA(isA<HoldKeyControllerException>()),
      );
      expect(f.controller.running, true);
      expect(f.controller.cleanupPending, true);
      expect(old.disables, 1);
      old.emit(HoldKeyAction.start);
      old.emit(HoldKeyAction.send);
      expect(f.log, ['start', 'cancel']);
      old.disableFails = false;
      await f.controller.sync();
      expect(old.disables, 2);
      expect(f.controller.cleanupPending, false);
      expect(f.controller.running, false);
      await f.controller.dispose();
    },
  );
  test('held disable blocks replacement enable and dispose completion until actual outcome', () async {
    final f = Fixture();
    addTearDown(f.settings.dispose);
    await f.settings.setEnabled(true);
    await f.controller.sync();
    final old = f.bridges.single;
    old.hold = 'disable';
    await f.settings.setKey(HoldKey.fn);
    final replacement = f.controller.sync();
    await old.entered.future;
    expect(f.controller.cleanupPending, true);
    expect(f.controller.running, true);
    expect(f.bridges.length, 1);
    final disposed = f.controller.dispose();
    var done = false;
    disposed.then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, false);
    old.release.complete();
    await Future.wait([replacement, disposed]);
    expect(f.bridges.length, 1);
    expect(f.controller.running, false);
    expect(old.disables, 1);
  });
  test('OFF before ON creates only fresh candidate and reset cancels current recording', () async {
    final f = Fixture();
    addTearDown(f.settings.dispose);
    final off = f.controller.sync();
    await f.settings.setEnabled(true);
    final on = f.controller.sync();
    await Future.wait([off, on]);
    expect(f.bridges.length, 1);
    final b = f.bridges.single;
    b.emit(HoldKeyAction.start);
    f.controller.reset();
    expect(f.log, ['start', 'cancel']);
    await f.controller.dispose();
  });
  test('live settings change without sync still blocks stale publication and callbacks', () async {
    final f = Fixture();
    addTearDown(f.settings.dispose);
    await f.settings.setEnabled(true);
    f.configure = (b) => b.hold = 'enable';
    final work = f.controller.sync();
    while (f.bridges.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final b = f.bridges.single;
    await b.entered.future;
    await f.settings.setEnabled(false);
    b.release.complete();
    await work;
    expect(f.controller.running, false);
    b.emit(HoldKeyAction.start);
    expect(f.log, isEmpty);
    await f.controller.dispose();
  });
  test(
    'failed dispose can retry cleanup but sync cannot revive disposed owner',
    () async {
      final f = Fixture();
      addTearDown(f.settings.dispose);
      await f.settings.setEnabled(true);
      await f.controller.sync();
      final b = f.bridges.single;
      b.disableFails = true;
      await expectLater(
        f.controller.dispose(),
        throwsA(isA<HoldKeyControllerException>()),
      );
      expect(f.controller.cleanupPending, true);
      await f.controller.sync();
      expect(f.bridges.length, 1);
      b.disableFails = false;
      await f.controller.dispose();
      expect(f.controller.running, false);
    },
  );
}
