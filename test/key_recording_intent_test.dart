import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:local_bluey/services/audio_capture.dart';
import 'package:local_bluey/services/key_recording_intent.dart';

class _SynchronousTemp implements Directory {
  _SynchronousTemp(this.path);
  @override
  final String path;
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Driver implements RecorderDriver {
  String? hold, fail, path;
  bool permission = true, on = false, partialStart = false, nullStop = false;
  int starts = 0, stops = 0, disposals = 0;
  final entered = Completer<void>(), release = Completer<void>();
  Future<void> stage(String name) async {
    if (hold == name) {
      hold = null;
      entered.complete();
      await release.future;
    }
    if (fail == name) throw StateError('private recorder');
  }

  @override
  Future<bool> hasPermission() async {
    await stage('permission');
    return permission;
  }

  @override
  Future<void> start(String p) async {
    starts++;
    path = p;
    if (partialStart) {
      on = true;
      File(p).writeAsStringSync('partial');
      throw StateError('private partial start');
    }
    await stage('start');
    File(p).writeAsStringSync('synthetic');
    on = true;
  }

  @override
  Future<String?> stop() async {
    stops++;
    await stage('stop');
    on = false;
    return nullStop ? null : path;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    if (fail == 'dispose') throw StateError('private dispose');
    on = false;
  }
}

class Fixture {
  final driver = Driver();
  late final Directory dir;
  late final AudioCapture capture;
  late final KeyRecordingIntent owner;
  final delivered = <String>[];
  bool deleteFail = false, allowed = true;
  Completer<void>? deleteEntered, deleteGate;
  var tempFail = false;
  int tempIndex = 0;
  Future<void> init() async {
    dir = Directory.systemTemp.createTempSync('key-fixture');
    capture = AudioCapture(
      driver: driver,
      tempDirProvider: () async {
        if (tempFail) throw StateError('private');
        return Directory('${dir.path}/session-${tempIndex++}')..createSync();
      },
      deleteFile: (file) async {
        if (!(deleteEntered?.isCompleted ?? true)) deleteEntered!.complete();
        if (deleteGate != null) await deleteGate!.future;
        if (deleteFail) throw StateError('private delete');
        if (await file.exists()) await file.delete();
      },
    );
    owner = KeyRecordingIntent(
      capture: capture,
      allowed: () => allowed,
      deliver: (file) async {
        delivered.add(file.path);
        await file.delete();
      },
      delete: (file) async {
        if (!(deleteEntered?.isCompleted ?? true)) deleteEntered!.complete();
        if (deleteGate != null) await deleteGate!.future;
        if (deleteFail) throw StateError('private delete');
        if (await file.exists()) await file.delete();
      },
    );
  }

  Future<void> finish() async {
    driver.fail = null;
    deleteFail = false;
    try {
      await owner.disposeIntent();
    } catch (_) {}
    owner.dispose();
    await capture.dispose();
    dir.deleteSync(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final allowed in [false, true]) {
    test('optional recover queued entry gate allowed=$allowed', () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      f.driver.partialStart = true;
      await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
      f.driver.partialStart = false;
      if (allowed) {
        await f.owner.recover(canEnter: () => true);
        expect(f.driver.stops, 1);
      } else {
        await expectLater(
          f.owner.recover(canEnter: () => false),
          throwsA(isA<KeyRecordingException>()),
        );
        expect(f.driver.stops, 0);
        expect(f.owner.cleanupPending, true);
      }
      expect(f.delivered, isEmpty);
    });
  }
  test('default direct recover queued cleanup under kill preserved', () async {
    final f = Fixture();
    await f.init();
    addTearDown(f.finish);
    f.driver.partialStart = true;
    await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
    f.driver.partialStart = false;
    f.owner.addListener(() {
      if (f.owner.status == KeyRecordingStatus.pending) f.allowed = false;
    });
    await f.owner.recover();
    expect(f.driver.stops, 1);
    expect(f.owner.cleanupPending, false);
    expect(f.delivered, isEmpty);
  });
  for (final stage in ['permission', 'start', 'stop']) {
    for (final end in ['send', 'cancel', 'dispose', 'fresh']) {
      test(
        'entered $stage versus $end owns effects and file delivery',
        () async {
          final f = Fixture();
          await f.init();
          addTearDown(f.finish);
          f.driver.hold = stage;
          final start = f.owner.start();
          Future<void>? sending;
          if (stage == 'stop') {
            await start;
            sending = f.owner.send();
          }
          await f.driver.entered.future;
          Future<void> endWork;
          switch (end) {
            case 'send':
              endWork = f.owner.send();
            case 'cancel':
              endWork = f.owner.cancel();
            case 'dispose':
              endWork = f.owner.disposeIntent();
            default:
              endWork = f.owner.start();
          }
          f.driver.release.complete();
          await Future.wait([start, ?sending, endWork]);
          if (stage == 'permission' && end != 'fresh') {
            expect(f.driver.starts, 0);
          }
          if (end == 'fresh') {
            expect(f.driver.on, true);
            expect(f.delivered, isEmpty);
          } else {
            expect(f.driver.on, false);
            expect(
              f.delivered.length,
              end == 'send' && stage != 'permission' ? 1 : 0,
            );
          }
          if (end != 'fresh') expect(f.owner.cleanupPending, false);
          if (end == 'send') {
            await f.owner.send();
            expect(f.delivered.length, stage == 'permission' ? 0 : 1);
          }
        },
      );
    }
  }
  for (final stage in ['permission', 'start', 'stop']) {
    test('$stage failure generic retained state explicit recovery', () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      f.driver.fail = stage;
      if (stage == 'stop') {
        await f.owner.start();
        await expectLater(
          f.owner.send(),
          throwsA(isA<KeyRecordingException>()),
        );
        expect(f.owner.cleanupPending, true);
      } else {
        await expectLater(
          f.owner.start(),
          throwsA(isA<KeyRecordingException>()),
        );
      }
      expect(
        f.owner.status,
        stage == 'permission'
            ? KeyRecordingStatus.failed
            : KeyRecordingStatus.uncertain,
      );
      f.driver.fail = null;
      if (stage == 'permission') {
        await f.owner.cancel();
        await f.owner.start();
        await f.owner.send();
        expect(f.delivered.length, 1);
      } else {
        expect(f.owner.cleanupPending, true);
        await expectLater(
          f.owner.start(),
          throwsA(isA<KeyRecordingException>()),
        );
        expect(f.owner.cleanupPending, true);
      }
    });
  }
  test('reentrant pending listener cancel prevents not-yet-entered permission/start', () async {
    final f = Fixture();
    await f.init();
    addTearDown(f.finish);
    Future<void>? canceled;
    f.owner.addListener(() {
      if (f.owner.status == KeyRecordingStatus.pending) {
        canceled = f.owner.cancel();
      }
    });
    await f.owner.start();
    await canceled;
    expect(f.driver.starts, 0);
    expect(f.owner.status, KeyRecordingStatus.idle);
  });
  test(
    'disposed capture-owned delete failure remains uncertain without revival',
    () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      await f.owner.start();
      f.deleteFail = true;
      await expectLater(
        f.owner.disposeIntent(),
        throwsA(isA<KeyRecordingException>()),
      );
      expect(f.owner.cleanupPending, true);
      f.deleteFail = false;
      await expectLater(
        f.owner.disposeIntent(),
        throwsA(isA<KeyRecordingException>()),
      );
      expect(
        f.owner.cleanupPending,
        true,
      ); // Disposed owner cannot recover/revive.
    },
  );
  for (final failure in ['partial-start', 'stop']) {
    test(
      '$failure uncertainty survives blocked fresh start send cancel dispose with no delivery',
      () async {
        final f = Fixture();
        await f.init();
        addTearDown(f.finish);
        if (failure == 'partial-start') {
          f.driver.partialStart = true;
          await expectLater(
            f.owner.start(),
            throwsA(isA<KeyRecordingException>()),
          );
        } else {
          await f.owner.start();
          f.driver.fail = 'stop';
          await expectLater(
            f.owner.send(),
            throwsA(isA<KeyRecordingException>()),
          );
        }
        expect(f.driver.on, true);
        final stops = f.driver.stops;
        final starts = f.driver.starts;
        f.driver.fail = null;
        f.driver.partialStart = false;
        await expectLater(
          f.owner.start(),
          throwsA(isA<KeyRecordingException>()),
        );
        await expectLater(
          f.owner.send(),
          throwsA(isA<KeyRecordingException>()),
        );
        await expectLater(
          f.owner.cancel(),
          throwsA(isA<KeyRecordingException>()),
        );
        await expectLater(
          f.owner.disposeIntent(),
          throwsA(isA<KeyRecordingException>()),
        );
        expect(f.owner.cleanupPending, true);
        expect(f.driver.starts, starts);
        expect(f.driver.stops, stops);
        expect(f.delivered, isEmpty);
        expect(f.driver.on, true);
      },
    );
  }
  for (final failure in [
    'partial-start',
    'stop',
    'delete',
    'dispose',
    'permission',
    'start',
  ]) {
    test(
      'same main close helper attempts driver disposal once after $failure',
      () async {
        final f = Fixture();
        await f.init();
        addTearDown(f.finish);
        Future<void>? started;
        if (failure == 'partial-start') {
          f.driver.partialStart = true;
          await expectLater(
            f.owner.start(),
            throwsA(isA<KeyRecordingException>()),
          );
        } else if (failure == 'permission' || failure == 'start') {
          f.driver.hold = failure;
          started = f.owner.start();
          await f.driver.entered.future;
        } else {
          await f.owner.start();
          if (failure == 'stop') f.driver.fail = 'stop';
          if (failure == 'delete') f.deleteFail = true;
          if (failure == 'dispose') f.driver.fail = 'dispose';
        }
        final close = f.owner.closeCapture(), again = f.owner.closeCapture();
        expect(identical(close, again), true);
        if (started != null) {
          f.driver.release.complete();
          await started;
        }
        await Future.wait([close, again]);
        expect(f.driver.disposals, 1);
        expect(
          f.owner.closeFailed,
          ['partial-start', 'stop', 'delete', 'dispose'].contains(failure),
        );
        if (['partial-start', 'stop', 'delete'].contains(failure)) {
          expect(f.owner.cleanupPending, true);
        }
        expect(f.delivered, isEmpty);
        await f.owner.closeCapture();
        expect(f.driver.disposals, 1);
      },
    );
  }
  test(
    'capture-owned delete failure requires dedicated explicit recovery',
    () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      await f.owner.start();
      f.deleteFail = true;
      await expectLater(
        f.owner.cancel(),
        throwsA(isA<KeyRecordingException>()),
      );
      expect(f.owner.cleanupPending, true);
      expect(File(f.driver.path!).existsSync(), true);
      f.deleteFail = false;
      await expectLater(
        f.owner.cancel(),
        throwsA(isA<KeyRecordingException>()),
      );
      await f.owner.recover();
      expect(f.owner.cleanupPending, false);
      expect(File(f.driver.path!).existsSync(), false);
      expect(f.delivered, isEmpty);
    },
  );
  test(
    'kill during entered permission blocks start even without cancel callback',
    () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      f.driver.hold = 'permission';
      final work = f.owner.start();
      await f.driver.entered.future;
      f.allowed = false;
      f.driver.release.complete();
      await work;
      expect(f.driver.starts, 0);
      f.allowed = true;
      await f.owner.start();
      expect(f.driver.starts, 1);
    },
  );
  test(
    'denied permission and dispose before future start are honest',
    () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      f.driver.permission = false;
      await f.owner.start();
      expect(f.owner.status, KeyRecordingStatus.denied);
      await f.owner.send();
      expect(f.owner.status, KeyRecordingStatus.denied);
      await f.owner.disposeIntent();
      await f.owner.start();
      expect(f.driver.starts, 0);
    },
  );
  test('actual main source distinct key send preserves ordinary face release and phone section', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('onSend: _onKeyHoldSend'));
    expect(source, contains('Future<void> _onHoldEnd() async'));
    expect(source, contains('unawaited(_disposeKeyCapture())'));
    expect(source, contains('await _keyRecording.closeCapture();'));
    expect(source, contains('allowed: () => mounted && !_safety.killed'));
  });
  for (final failure in ['partial', 'stop']) {
    test(
      'explicit $failure recovery failed attempt retains then cleans without delivery',
      () async {
        final f = Fixture();
        await f.init();
        addTearDown(f.finish);
        if (failure == 'partial') {
          f.driver.partialStart = true;
          await expectLater(
            f.owner.start(),
            throwsA(isA<KeyRecordingException>()),
          );
        } else {
          await f.owner.start();
          f.driver.fail = 'stop';
          await expectLater(
            f.owner.send(),
            throwsA(isA<KeyRecordingException>()),
          );
        }
        f.driver.fail = 'stop';
        await expectLater(
          f.owner.recover(),
          throwsA(isA<KeyRecordingException>()),
        );
        expect(f.owner.cleanupPending, true);
        expect(f.driver.on, true);
        f.driver.fail = null;
        f.driver.partialStart = false;
        final old = f.driver.path!;
        await f.owner.recover();
        expect(f.driver.on, false);
        expect(f.owner.cleanupPending, false);
        expect(File(old).existsSync(), false);
        expect(f.delivered, isEmpty);
        expect(f.owner.status, KeyRecordingStatus.idle);
        await f.owner.start();
        await f.owner.send();
        expect(f.delivered.length, 1);
      },
    );
  }
  test(
    'explicit recovery held deletion concurrent completion remains pending',
    () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      f.driver.partialStart = true;
      await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
      f.deleteEntered = Completer<void>();
      f.deleteGate = Completer<void>();
      final a = f.owner.recover(), b = f.owner.recover();
      expect(b, same(a));
      await f.deleteEntered!.future;
      var done = false;
      a.then((_) => done = true);
      await Future<void>.value();
      expect(done, false);
      expect(f.driver.stops, 1);
      f.deleteGate!.complete();
      await Future.wait([a, b]);
      expect(done, true);
      expect(f.owner.cleanupPending, false);
      expect(f.delivered, isEmpty);
    },
  );
  test(
    'explicit recovery held stop reentrant retry joins completion',
    () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      f.driver.partialStart = true;
      await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
      f.driver.hold = 'stop';
      Future<void>? reentrant;
      f.owner.addListener(() {
        if (f.owner.status == KeyRecordingStatus.pending) {
          reentrant = f.owner.recover();
        }
      });
      final a = f.owner.recover(), b = f.owner.recover();
      expect(b, same(a));
      expect(reentrant, same(a));
      await f.driver.entered.future;
      var done = false;
      a.then((_) => done = true);
      await Future<void>.value();
      expect(done, false);
      f.driver.release.complete();
      await Future.wait([a, b]);
      expect(done, true);
      expect(f.delivered, isEmpty);
    },
  );
  test(
    'busy legacy start no key claim send cancel recovery zero effects',
    () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      f.driver.hold = 'start';
      final legacy = f.capture.start();
      await f.driver.entered.future;
      await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
      expect(f.owner.cleanupPending, false);
      await f.owner.send();
      await f.owner.cancel();
      await f.owner.recover();
      expect(f.driver.stops, 0);
      expect(f.driver.starts, 1);
      expect(f.delivered, isEmpty);
      f.driver.release.complete();
      await legacy;
      final file = await f.capture.stop();
      await AudioCapture.deleteQuietly(file);
    },
  );
  test('external consumption fresh legacy stale key send cancel recovery zero effects', () async {
    final f = Fixture();
    await f.init();
    addTearDown(f.finish);
    await f.owner.start();
    final external = await f.capture.stop();
    final retained = external!;
    await f.capture.start();
    final stops = f.driver.stops;
    await f.owner.send();
    await f.owner.cancel();
    await f.owner.recover();
    expect(f.driver.stops, stops);
    expect(f.driver.on, true);
    expect(f.delivered, isEmpty);
    expect(retained.existsSync(), true);
    final current = await f.capture.stop();
    await AudioCapture.deleteQuietly(current);
  });
  test(
    'successful current driver null explicit recovery is no-delivery receipt',
    () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      f.driver.partialStart = true;
      f.driver.nullStop = true;
      await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
      final exact = f.driver.path!;
      await f.owner.recover();
      final stops = f.driver.stops;
      await f.owner.recover();
      expect(f.driver.stops, stops);
      expect(File(exact).existsSync(), false);
      expect(f.owner.cleanupPending, false);
      expect(f.delivered, isEmpty);
    },
  );
  test('capture-owned deletion failure explicit retry never repeats confirmed stop', () async {
    final f = Fixture();
    await f.init();
    addTearDown(f.finish);
    await f.owner.start();
    f.deleteFail = true;
    await expectLater(f.owner.cancel(), throwsA(isA<KeyRecordingException>()));
    final stops = f.driver.stops, exact = f.driver.path!;
    await expectLater(f.owner.recover(), throwsA(isA<KeyRecordingException>()));
    expect(f.owner.cleanupPending, true);
    expect(File(exact).existsSync(), true);
    f.deleteFail = false;
    await f.owner.recover();
    expect(f.driver.stops, stops);
    expect(File(exact).existsSync(), false);
    expect(f.delivered, isEmpty);
    expect(f.owner.cleanupPending, false);
  });
  for (final end in ['fresh', 'cancel', 'kill', 'dispose']) {
    test(
      'entered explicit recovery superseded by $end no stale publication',
      () async {
        final f = Fixture();
        await f.init();
        addTearDown(f.finish);
        f.driver.partialStart = true;
        await expectLater(
          f.owner.start(),
          throwsA(isA<KeyRecordingException>()),
        );
        f.driver.partialStart = false;
        f.driver.hold = 'stop';
        final recover = f.owner.recover();
        await f.driver.entered.future;
        Future<void>? ending;
        if (end == 'fresh') ending = f.owner.start();
        if (end == 'cancel') ending = f.owner.cancel();
        if (end == 'kill') f.allowed = false;
        if (end == 'dispose') ending = f.owner.disposeIntent();
        final prior = f.owner.status;
        var notices = 0;
        f.owner.addListener(() => notices++);
        f.driver.release.complete();
        await recover;
        if (ending != null) await ending;
        expect(f.delivered, isEmpty);
        if (end == 'kill' || end == 'dispose') {
          expect(notices, 0);
          expect(f.owner.status, prior);
        }
        expect(f.driver.starts, end == 'fresh' ? 2 : 1);
      },
    );
  }
  test('no-driver-entry recovery clears only its receipt and fresh hold later works', () async {
    final f = Fixture();
    await f.init();
    addTearDown(f.finish);
    f.tempFail = true;
    await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
    expect(f.driver.starts, 0);
    expect(f.owner.cleanupPending, true);
    await f.owner.recover();
    expect(f.driver.stops, 0);
    expect(f.owner.cleanupPending, false);
    f.tempFail = false;
    await f.owner.start();
    await f.owner.send();
    expect(f.delivered.length, 1);
  });
  test(
    'disposed capture receipt retains key uncertainty without new driver stop',
    () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      f.driver.partialStart = true;
      await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
      f.driver.fail = 'stop';
      await expectLater(
        f.capture.dispose(),
        throwsA(isA<CaptureLifecycleException>()),
      );
      final stops = f.driver.stops;
      await expectLater(
        f.owner.recover(),
        throwsA(isA<KeyRecordingException>()),
      );
      expect(f.driver.stops, stops);
      expect(f.owner.cleanupPending, true);
      expect(f.delivered, isEmpty);
      expect(f.owner.status, KeyRecordingStatus.uncertain);
    },
  );
  test(
    'kill before explicit recovery allows retained cleanup only no publication',
    () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      f.driver.partialStart = true;
      await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
      f.allowed = false;
      final status = f.owner.status;
      var notices = 0;
      f.owner.addListener(() => notices++);
      await f.owner.recover();
      expect(notices, 0);
      expect(f.owner.status, status);
      expect(f.owner.cleanupPending, false);
      expect(f.delivered, isEmpty);
      expect(f.driver.starts, 1);
      await f.owner.start();
      expect(f.driver.starts, 1);
    },
  );
  test('synchronous recovery listener cancel preserves resource vs publication ordering', () async {
    final f = Fixture();
    await f.init();
    addTearDown(f.finish);
    f.driver.partialStart = true;
    await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
    Future<void>? cancel;
    var once = false;
    f.owner.addListener(() {
      if (!once && f.owner.status == KeyRecordingStatus.pending) {
        once = true;
        cancel = f.owner.cancel();
      }
    });
    await f.owner.recover();
    await cancel;
    expect(f.owner.status, KeyRecordingStatus.idle);
    expect(f.owner.cleanupPending, false);
    expect(f.driver.stops, 1);
    expect(f.delivered, isEmpty);
  });
  test('separately transferred key file failed delete cancel retries without capture stop', () async {
    final f = Fixture();
    await f.init();
    addTearDown(f.finish);
    await f.owner.start();
    f.driver.hold = 'stop';
    f.deleteFail = true;
    final sending = expectLater(
      f.owner.send(),
      throwsA(isA<KeyRecordingException>()),
    );
    await f.driver.entered.future;
    final canceling = expectLater(
      f.owner.cancel(),
      throwsA(isA<KeyRecordingException>()),
    );
    f.driver.release.complete();
    await Future.wait([sending, canceling]);
    final exact = f.driver.path!, stops = f.driver.stops;
    expect(File(exact).existsSync(), true);
    expect(f.owner.cleanupPending, true);
    f.deleteFail = false;
    await f.owner.cancel();
    expect(File(exact).existsSync(), false);
    expect(f.driver.stops, stops);
    expect(f.owner.cleanupPending, false);
    expect(f.delivered, isEmpty);
  });
  test('explicit recovery cannot hide retry behind fresh hold during retained failure', () async {
    final f = Fixture();
    await f.init();
    addTearDown(f.finish);
    f.driver.partialStart = true;
    await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
    final stops = f.driver.stops;
    f.driver.partialStart = false;
    await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
    expect(f.driver.stops, stops);
    expect(f.driver.starts, 1);
    await f.owner.recover();
    expect(f.driver.starts, 1);
    expect(f.delivered, isEmpty);
    await f.owner.start();
    expect(f.driver.starts, 2);
  });
  test(
    'disposed before recovery zero effects and retained capture uncertainty',
    () async {
      final f = Fixture();
      await f.init();
      addTearDown(f.finish);
      f.driver.partialStart = true;
      await expectLater(f.owner.start(), throwsA(isA<KeyRecordingException>()));
      await expectLater(
        f.owner.disposeIntent(),
        throwsA(isA<KeyRecordingException>()),
      );
      final starts = f.driver.starts,
          stops = f.driver.stops,
          disposals = f.driver.disposals;
      final exact = f.driver.path!;
      var notices = 0;
      f.owner.addListener(() => notices++);
      await f.owner.recover();
      await f.owner.start();
      await f.owner.send();
      expect(f.driver.starts, starts);
      expect(f.driver.stops, stops);
      expect(f.driver.disposals, disposals);
      expect(File(exact).existsSync(), true);
      expect(f.delivered, isEmpty);
      expect(notices, 0);
      expect(f.owner.cleanupPending, true);
    },
  );
  for (final recoveryFirst in [false, true]) {
    test(
      'key held cap send recovery exact owner recoveryFirst=$recoveryFirst',
      () {
        final dir = Directory.systemTemp.createTempSync('key-cap-recovery-');
        final delivered = <String>[], deleted = <String>[];
        fakeAsync((async) {
          final driver = Driver()..hold = 'stop';
          final capture = AudioCapture(
            driver: driver,
            maxDuration: const Duration(seconds: 1),
            tempDirProvider: () async => _SynchronousTemp(dir.path),
            deleteFile: (file) async {
              deleted.add(file.path);
              if (file.existsSync()) file.deleteSync();
            },
          );
          final owner = KeyRecordingIntent(
            capture: capture,
            deliver: (file) async {
              delivered.add(file.path);
              if (file.existsSync()) file.deleteSync();
            },
            delete: (file) async {
              deleted.add(file.path);
              if (file.existsSync()) file.deleteSync();
            },
          );
          owner.start();
          async.flushMicrotasks();
          expect(driver.starts, 1);
          final exact = driver.path!;
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
          expect(driver.entered.isCompleted, true);
          expect(driver.stops, 1);
          Future<void> send, recover;
          if (recoveryFirst) {
            recover = owner.recover();
            send = owner.send();
          } else {
            send = owner.send();
            recover = owner.recover();
          }
          var sent = false, recovered = false;
          send.then((_) => sent = true);
          recover.then((_) => recovered = true);
          async.flushMicrotasks();
          expect(sent, false);
          expect(recovered, false);
          driver.release.complete();
          async.flushMicrotasks();
          expect(sent, true);
          expect(recovered, true);
          expect(driver.stops, 1);
          expect(delivered, recoveryFirst ? isEmpty : [exact]);
          expect(deleted, recoveryFirst ? [exact] : isEmpty);
          expect(File(exact).existsSync(), false);
          expect(owner.cleanupPending, false);
          owner.disposeIntent();
          async.flushMicrotasks();
          owner.dispose();
          capture.dispose();
          async.flushMicrotasks();
        });
        dir.deleteSync(recursive: true);
      },
    );
  }
}
