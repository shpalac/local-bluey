import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/key_cleanup_caller.dart';
import 'package:local_bluey/services/key_recording_intent.dart';

import 'key_recording_intent_test.dart' show Fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Fixture f;
  late KeyCleanupCaller c;
  setUp(() async {
    f = Fixture();
    await f.init();
    c = KeyCleanupCaller(owner: f.owner, allowed: () => f.allowed);
  });
  tearDown(() async {
    c.dispose();
    await f.finish();
  });
  Future<void> fail() async {
    f.driver.partialStart = true;
    await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
    f.driver.partialStart = false;
  }

  test(
    'normal live acquisition never exposes retry and no automatic recovery',
    () async {
      await f.owner.start();
      expect(c.visible, false);
      expect(c.enabled, false);
      await c.retry();
      expect(f.driver.stops, 0);
      expect(f.driver.starts, 1);
      await f.owner.cancel();
      expect(c.visible, false);
    },
  );
  for (final stage in ['stop', 'delete']) {
    test(
      'actual held $stage concurrent reentrant retry joins full cleanup',
      () async {
        await fail();
        expect(c.enabled, true);
        if (stage == 'stop') {
          f.driver.hold = 'stop';
        } else {
          f.deleteEntered = Completer<void>();
          f.deleteGate = Completer<void>();
        }
        Future<void>? reentrant;
        c.addListener(() {
          if (c.loading) reentrant = c.retry();
        });
        final a = c.retry(), b = c.retry();
        expect(b, same(a));
        expect(reentrant, same(a));
        await (stage == 'stop'
            ? f.driver.entered.future
            : f.deleteEntered!.future);
        var done = false;
        a.then((_) => done = true);
        await Future<void>.value();
        expect(done, false);
        expect(c.visible, true);
        expect(c.enabled, false);
        if (stage == 'stop') {
          f.driver.release.complete();
        } else {
          f.deleteGate!.complete();
        }
        await Future.wait([a, b]);
        expect(done, true);
        expect(c.loading, false);
        expect(c.visible, false);
        expect(f.driver.stops, 1);
        expect(f.delivered, isEmpty);
        expect(File(f.driver.path!).existsSync(), false);
      },
    );
  }
  test('failed retry retains notice and explicit action re-enables', () async {
    await fail();
    f.driver.fail = 'stop';
    await c.retry();
    expect(c.failed, true);
    expect(c.enabled, true);
    f.driver.fail = null;
    await c.retry();
    expect(c.visible, false);
    expect(f.delivered, isEmpty);
  });
  for (final end in ['kill', 'dispose']) {
    test('$end before queued entry zero cleanup effects', () async {
      await fail();
      final retry = c.retry();
      if (end == 'kill') {
        f.allowed = false;
      } else {
        c.dispose();
      }
      await retry;
      expect(f.driver.stops, 0);
      expect(f.owner.cleanupPending, true);
      if (end == 'kill') {
        expect(c.loading, false);
        f.allowed = true;
        c.refreshGuard();
        expect(c.enabled, true);
        await c.retry();
        expect(c.visible, false);
      }
    });
    test('$end while entered cleanup settles without late notice', () async {
      await fail();
      f.driver.hold = 'stop';
      final retry = c.retry();
      await f.driver.entered.future;
      if (end == 'kill') {
        f.allowed = false;
      } else {
        c.dispose();
      }
      var notices = 0;
      if (end == 'kill') c.addListener(() => notices++);
      f.driver.release.complete();
      await retry;
      expect(notices, 0);
      expect(f.delivered, isEmpty);
      if (end == 'kill') {
        expect(c.loading, false);
        f.allowed = true;
        c.refreshGuard();
        expect(c.visible, false);
      }
    });
  }
  test(
    'reentrant disposal during pending notification never enters owner',
    () async {
      await fail();
      c.addListener(() {
        if (c.loading) c.dispose();
      });
      await c.retry();
      expect(f.driver.stops, 0);
    },
  );
  test('no-entry positive receipt hides notice without driver stop', () async {
    f.tempFail = true;
    await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
    await c.retry();
    expect(c.visible, false);
    expect(f.driver.stops, 0);
  });
  test('failed stop then external transfer/new legacy retry touches neither resource', () async {
    await f.owner.start();
    f.driver.fail = 'stop';
    await expectLater(f.owner.send(), throwsA(isA<KeyRecordingException>()));
    f.driver.fail = null;
    final old = await f.capture.stop();
    await f.capture.start();
    final stops = f.driver.stops;
    await c.retry();
    expect(f.driver.stops, stops);
    expect(f.driver.on, true);
    expect(old!.existsSync(), true);
    expect(c.visible, false);
    await old.delete();
  });
  test(
    'capture-owned deletion failure retry is explicit and file-only',
    () async {
      await f.owner.start();
      f.deleteFail = true;
      await expectLater(
        f.owner.cancel(),
        throwsA(isA<KeyRecordingException>()),
      );
      await c.retry();
      expect(c.visible, true);
      final stops = f.driver.stops;
      f.deleteFail = false;
      await c.retry();
      expect(f.driver.stops, stops);
      expect(c.visible, false);
    },
  );
  test(
    'separate key-owned deletion explicit retry never stops again',
    () async {
      await f.owner.start();
      f.driver.hold = 'stop';
      f.deleteFail = true;
      final sending = expectLater(
        f.owner.send(),
        throwsA(isA<KeyRecordingException>()),
      );
      await f.driver.entered.future;
      final canceled = expectLater(
        f.owner.cancel(),
        throwsA(isA<KeyRecordingException>()),
      );
      f.driver.release.complete();
      await Future.wait([sending, canceled]);
      expect(c.visible, true);
      final stops = f.driver.stops;
      await c.retry();
      expect(c.failed, true);
      expect(c.enabled, true);
      f.deleteFail = false;
      await c.retry();
      expect(c.visible, false);
      expect(f.driver.stops, stops);
      expect(f.delivered, isEmpty);
    },
  );
  test(
    'actual disposed owner remains uncertainty and starts nothing',
    () async {
      await fail();
      await expectLater(
        f.owner.disposeIntent(),
        throwsA(isA<KeyRecordingException>()),
      );
      final stops = f.driver.stops;
      await c.retry();
      expect(c.visible, true);
      expect(c.enabled, true);
      expect(f.driver.stops, stops);
      expect(f.driver.starts, 1);
      expect(f.delivered, isEmpty);
    },
  );
  test(
    'nested guard refresh then disposal survives notifier lifecycle',
    () async {
      await fail();
      var nested = false;
      c.addListener(() {
        if (!nested) {
          nested = true;
          c.refreshGuard();
          c.dispose();
        }
      });
      await c.retry();
      expect(f.driver.stops, 0);
      expect(c.loading, false);
    },
  );
  test('kill notification guard change never recovers automatically', () async {
    await fail();
    f.allowed = false;
    c.refreshGuard();
    await c.retry();
    expect(f.driver.stops, 0);
    expect(c.enabled, false);
    f.allowed = true;
    c.refreshGuard();
    expect(c.enabled, true);
    expect(f.driver.stops, 0);
  });
  test(
    'dispose during owner pending before queued cleanup entry zero stop',
    () async {
      await fail();
      f.owner.addListener(() {
        if (f.owner.status == KeyRecordingStatus.pending) c.dispose();
      });
      await c.retry();
      expect(f.driver.stops, 0);
    },
  );
  test('kill during entered failed cleanup re-enables after unkill', () async {
    await fail();
    f.driver.hold = 'stop';
    f.driver.fail = 'stop';
    final retry = c.retry();
    await f.driver.entered.future;
    f.allowed = false;
    f.driver.release.complete();
    await retry;
    f.allowed = true;
    c.refreshGuard();
    expect(c.visible, true);
    expect(c.enabled, true);
  });
  test('caller pending owner publication kill aborts queued stop', () async {
    await fail();
    f.owner.addListener(() {
      if (f.owner.status == KeyRecordingStatus.pending) f.allowed = false;
    });
    await c.retry();
    expect(f.driver.stops, 0);
    expect(c.loading, false);
    f.allowed = true;
    c.refreshGuard();
    expect(c.enabled, true);
  });
  test('stale failed retry evidence never exposes normal fresh hold', () async {
    await fail();
    f.driver.fail = 'stop';
    await c.retry();
    expect(c.failed, true);
    f.driver.fail = null;
    await f.owner.recover();
    await f.owner.start();
    expect(c.visible, false);
    expect(c.enabled, false);
    final stops = f.driver.stops;
    await c.retry();
    expect(f.driver.stops, stops);
    expect(f.driver.on, true);
  });
  test('entered aborted failure then allowed explicit action repairs only old file', () async {
    await fail();
    f.driver.hold = 'stop';
    f.driver.fail = 'stop';
    final retry = c.retry();
    await f.driver.entered.future;
    f.allowed = false;
    f.driver.release.complete();
    await retry;
    f.allowed = true;
    c.refreshGuard();
    expect(c.enabled, true);
    f.driver.fail = null;
    await c.retry();
    expect(c.visible, false);
    expect(f.driver.starts, 1);
    expect(f.delivered, isEmpty);
  });
  test('main exact two branches/lifecycle/source route only', () {
    final s = File('lib/main.dart').readAsStringSync();
    expect('KeyCleanupNotice(caller: _keyCleanup)'.allMatches(s).length, 2);
    expect(s, contains('_keyCleanup.dispose();'));
    expect(s, contains('owner: _keyRecording'));
    expect(s, contains('allowed: () => mounted && !_safety.killed'));
  });
}
