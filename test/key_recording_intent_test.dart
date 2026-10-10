import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/audio_capture.dart';
import 'package:local_bluey/services/key_recording_intent.dart';

class Driver implements RecorderDriver {
  String? hold, fail, path;
  bool permission = true, on = false, partialStart = false;
  int starts = 0, stops = 0;
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
    return path;
  }

  @override
  Future<void> dispose() async {
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
  Future<void> init() async {
    dir = Directory.systemTemp.createTempSync('key-fixture');
    capture = AudioCapture(driver: driver, tempDirProvider: () async => dir);
    owner = KeyRecordingIntent(
      capture: capture,
      allowed: () => allowed,
      deliver: (file) async {
        delivered.add(file.path);
        await file.delete();
      },
      delete: (file) async {
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
    'dispose delete uncertainty remains owned and can be explicitly retried',
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
      await f.owner.disposeIntent();
      expect(f.owner.cleanupPending, false);
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
  test(
    'failed delete retains exact file until explicit cancel retry',
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
      await f.owner.cancel();
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
    expect(source, contains('allowed: () => mounted && !_safety.killed'));
  });
}
