import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/hold_key.dart';
import 'package:local_bluey/services/hold_key_bridge.dart';
import 'package:local_bluey/services/hold_key_controller.dart';

class Bridge extends HoldKeyBridge {
  Bridge(HoldKeyMachine m, void Function(HoldKeyAction) a)
    : super(machine: m, onAction: a);
  bool on = false;
  @override
  bool get enabled => on;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> enable() async => on = true;
  @override
  Future<void> disable() async {
    on = false;
    emit(HoldKeyAction.cancel);
  }

  @override
  void reset() => emit(HoldKeyAction.cancel);
  void emit(HoldKeyAction a) => onAction(a);
}

class Fixture {
  final data = <String, Object>{};
  final bridges = <Bridge>[];
  final entered = Completer<void>(), release = Completer<void>();
  HoldKeyAction? hold, fail;
  bool syncThrow = false;
  final calls = <HoldKeyAction>[];
  Future<void> callback(HoldKeyAction a) {
    calls.add(a);
    if (syncThrow && fail == a) throw StateError('private synchronous');
    return () async {
      if (hold == a) {
        entered.complete();
        await release.future;
      }
      if (fail == a) throw StateError('secret path');
    }();
  }

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
  late final c = HoldKeyController(
    settings: settings,
    onStart: () => callback(HoldKeyAction.start),
    onSend: () => callback(HoldKeyAction.send),
    onCancel: () => callback(HoldKeyAction.cancel),
    createBridge: (m, a) {
      final b = Bridge(m, a);
      bridges.add(b);
      return b;
    },
  );
  Future<void> start() async {
    await settings.setEnabled(true);
    await c.sync();
  }

  Future<void> finish() async {
    await c.dispose();
    settings.dispose();
    c.actionResult.dispose();
  }
}

Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final action in [
    HoldKeyAction.start,
    HoldKeyAction.send,
    HoldKeyAction.cancel,
  ]) {
    for (final failure in [false, true]) {
      test(
        'entered $action success/failure=$failure safely observed then explicit new action clears',
        () async {
          final f = Fixture()
            ..hold = action
            ..fail = failure ? action : null;
          await f.start();
          f.bridges.single.emit(action);
          await f.entered.future;
          expect(f.c.actionResult.value!.action, action);
          expect(
            f.c.actionResult.value!.status,
            HoldKeyActionStatus.dispatched,
          );
          f.release.complete();
          await flush();
          expect(
            f.c.actionResult.value!.status,
            failure
                ? HoldKeyActionStatus.failed
                : HoldKeyActionStatus.completed,
          );
          expect(
            f.c.actionResult.value!.error,
            failure ? isNot(contains('secret')) : isNull,
          );
          f.hold = f.fail = null;
          f.bridges.single.emit(HoldKeyAction.send);
          await flush();
          expect(f.c.actionResult.value!.status, HoldKeyActionStatus.completed);
          await f.finish();
        },
      );
    }
    test('$action synchronous invocation throw contained', () async {
      final f = Fixture()
        ..fail = action
        ..syncThrow = true;
      await f.start();
      f.bridges.single.emit(action);
      expect(f.c.actionResult.value!.status, HoldKeyActionStatus.failed);
      f.fail = null;
      await f.finish();
    });
    for (final change in ['new-action', 'replace', 'dispose']) {
      test(
        'late entered $action rejection after $change cannot publish stale failure',
        () async {
          final f = Fixture()
            ..hold = action
            ..fail = action;
          await f.start();
          f.bridges.single.emit(action);
          await f.entered.future;
          // Reset/cleanup cancellation should not use the same held fixture again.
          f.hold = null;
          if (change == 'new-action') {
            f.bridges.single.emit(
              action == HoldKeyAction.send
                  ? HoldKeyAction.cancel
                  : HoldKeyAction.send,
            );
            await flush();
          } else if (change == 'replace') {
            await f.settings.setKey(HoldKey.fn);
            await f.c.sync();
            f.bridges.last.emit(HoldKeyAction.send);
            await flush();
          } else {
            await f.c.dispose();
          }
          final latest = f.c.actionResult.value;
          f.release.complete();
          await flush();
          expect(f.c.actionResult.value, same(latest));
          if (change == 'dispose') expect(latest, isNull);
          f.fail = null;
          await f.finish();
        },
      );
    }
  }
  for (final cleanup in ['reset', 'off', 'dispose']) {
    test(
      '$cleanup cancellation rejection handled without native stop promise',
      () async {
        final f = Fixture();
        await f.start();
        f.bridges.single.emit(HoldKeyAction.start);
        await flush();
        f.fail = HoldKeyAction.cancel;
        if (cleanup == 'reset') {
          f.c.reset();
        } else if (cleanup == 'off') {
          await f.settings.setEnabled(false);
          await f.c.sync();
        } else {
          await f.c.dispose();
        }
        await flush();
        expect(f.calls, [HoldKeyAction.start, HoldKeyAction.cancel]);
        expect(
          f.c.actionResult.value?.status,
          cleanup == 'dispose' ? null : HoldKeyActionStatus.failed,
        );
        f.fail = null;
        await f.finish();
      },
    );
  }
  test(
    'reentrant dispatched-result disposal prevents start invocation',
    () async {
      final f = Fixture();
      await f.start();
      Future<void>? stopped;
      f.c.actionResult.addListener(() {
        if (f.c.actionResult.value?.status == HoldKeyActionStatus.dispatched) {
          stopped = f.c.dispose();
        }
      });
      f.bridges.single.emit(HoldKeyAction.start);
      await stopped;
      await flush();
      expect(f.calls, [HoldKeyAction.cancel]);
      expect(f.c.actionResult.value, isNull);
      await f.finish();
    },
  );
  test('zero uncaught zone errors from entered current and disposed callback failures', () async {
    final uncaught = <Object>[];
    final done = Completer<void>();
    runZonedGuarded(() async {
      try {
        final f = Fixture()
          ..hold = HoldKeyAction.start
          ..fail = HoldKeyAction.start;
        await f.start();
        f.bridges.single.emit(HoldKeyAction.start);
        await f.entered.future;
        f.hold = null;
        f.fail = HoldKeyAction.cancel;
        await f.c.dispose();
        f.release.complete();
        await flush();
        await f.finish();
      } finally {
        done.complete();
      }
    }, (e, _) => uncaught.add(e));
    await done.future;
    expect(uncaught, isEmpty);
  });
}
