import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/audio_capture.dart';

class _Temp implements Directory {
  _Temp(this.path);
  @override
  final String path;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => const Stream.empty();
}

class _Driver implements RecorderDriver {
  String? path;
  bool open = false, partial = false, failStop = false, failDispose = false;
  bool nullStop = false;
  int starts = 0, stops = 0, disposals = 0;
  Completer<void>? startEntered, startGate, stopEntered, stopGate;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start(String value) async {
    starts++;
    path = value;
    startEntered?.complete();
    if (startGate != null) await startGate!.future;
    File(value).writeAsStringSync('synthetic');
    open = true;
    if (partial) throw StateError('private');
  }

  @override
  Future<String?> stop() async {
    stops++;
    if (!(stopEntered?.isCompleted ?? true)) stopEntered!.complete();
    if (stopGate != null) await stopGate!.future;
    if (failStop) throw StateError('private');
    open = false;
    return nullStop ? null : path;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    if (failDispose) throw StateError('private');
    // Disposal alone deliberately does not prove stop.
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late _Driver driver;
  late AudioCapture capture;
  var failDelete = false;
  Completer<void>? deleteEntered, deleteGate;
  late List<String> deletes;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('capture-identity-');
    driver = _Driver();
    failDelete = false;
    deleteEntered = deleteGate = null;
    deletes = [];
    capture = AudioCapture(
      driver: driver,
      tempDirProvider: () async => dir,
      deleteFile: (file) async {
        deletes.add(file.path);
        if (!(deleteEntered?.isCompleted ?? true)) deleteEntered!.complete();
        if (deleteGate != null) await deleteGate!.future;
        if (failDelete) throw StateError('private path');
        if (await file.exists()) await file.delete();
      },
    );
  });
  tearDown(() async {
    driver.failStop = driver.failDispose = false;
    failDelete = false;
    if (!(driver.startGate?.isCompleted ?? true)) driver.startGate!.complete();
    if (!(driver.stopGate?.isCompleted ?? true)) driver.stopGate!.complete();
    if (!(deleteGate?.isCompleted ?? true)) deleteGate!.complete();
    await capture.dispose();
    dir.deleteSync(recursive: true);
  });

  for (final nullStop in [false, true]) {
    test(
      'partial start retains identity and current cleanup null=$nullStop',
      () async {
        driver.partial = true;
        driver.nullStop = nullStop;
        final token = capture.acquire()!;
        await expectLater(
          token.started,
          throwsA(isA<CaptureLifecycleException>()),
        );
        expect(token.outcome, isNull);
        expect(driver.open, true);
        final exact = capture.debugPath!;
        expect(await capture.cleanup(token), CaptureCleanupOutcome.cleaned);
        expect(token.outcome, CaptureCleanupOutcome.cleaned);
        expect(driver.stops, 1);
        expect(driver.open, false);
        expect(File(exact).existsSync(), false);
        expect(capture.cleanupPending, false);
        expect(await capture.stop(), null);
        expect(await capture.cleanup(token), CaptureCleanupOutcome.cleaned);
        expect(driver.stops, 1); // Wrapper null did not clean anything.
      },
    );
  }
  test(
    'failed still-open retry retains token and joins actual held cleanup',
    () async {
      final token = capture.acquire()!;
      await token.started;
      driver.failStop = true;
      await expectLater(
        capture.cleanup(token),
        throwsA(isA<CaptureLifecycleException>()),
      );
      expect(token.outcome, isNull);
      expect(driver.open, true);
      expect(capture.acquire(), null);
      driver.failStop = false;
      driver.stopEntered = Completer<void>();
      driver.stopGate = Completer<void>();
      final a = capture.cleanup(token), b = capture.cleanup(token);
      expect(b, same(a));
      await driver.stopEntered!.future;
      var settled = false;
      a.then((_) => settled = true);
      await Future<void>.value();
      expect(settled, false);
      expect(driver.stops, 2);
      await expectLater(capture.start(), throwsStateError);
      expect(capture.acquire(), null);
      driver.stopGate!.complete();
      expect(await a, CaptureCleanupOutcome.cleaned);
      expect(await b, CaptureCleanupOutcome.cleaned);
      expect(settled, true);
      expect(driver.open, false);
    },
  );
  for (final nullStop in [false, true]) {
    test('held failed deletion file-only retry null=$nullStop', () async {
      driver.nullStop = nullStop;
      final token = capture.acquire()!;
      await token.started;
      final exact = capture.debugPath!;
      failDelete = true;
      await expectLater(
        capture.cleanup(token),
        throwsA(isA<CaptureLifecycleException>()),
      );
      expect(File(exact).existsSync(), true);
      expect(token.outcome, isNull);
      expect(driver.stops, 1);
      failDelete = false;
      deleteEntered = Completer<void>();
      deleteGate = Completer<void>();
      final a = capture.cleanup(token), b = capture.cleanup(token);
      expect(b, same(a));
      await deleteEntered!.future;
      var settled = false;
      a.then((_) => settled = true);
      await Future<void>.value();
      expect(settled, false);
      await expectLater(capture.start(), throwsStateError);
      expect(driver.stops, 1);
      deleteGate!.complete();
      expect(await a, CaptureCleanupOutcome.cleaned);
      await b;
      expect(deletes, [exact, exact]);
      expect(File(exact).existsSync(), false);
      expect(driver.stops, 1);
    });
  }
  test(
    'external consumed token then new legacy capture has zero stale effects',
    () async {
      final firstDir = Directory('${dir.path}/first')..createSync();
      final nextDir = Directory('${dir.path}/next')..createSync();
      var acquisitions = 0;
      capture = AudioCapture(
        driver: driver,
        tempDirProvider: () async => acquisitions++ == 0 ? firstDir : nextDir,
        deleteFile: (file) async {
          deletes.add(file.path);
          if (await file.exists()) await file.delete();
        },
      );
      final token = capture.acquire()!;
      await token.started;
      final old = await capture.stop();
      expect(old, isNotNull);
      expect(token.outcome, CaptureCleanupOutcome.transferred);
      // Stale cleanup must never touch the current legacy candidate.
      final oldPath = old!.path;
      await capture.start();
      final current = capture.debugPath!;
      expect(current, isNot(oldPath));
      expect(File(oldPath).existsSync(), true);
      final beforeStops = driver.stops, beforeDeletes = deletes.length;
      expect(await capture.cleanup(token), CaptureCleanupOutcome.transferred);
      expect(driver.open, true);
      expect(driver.stops, beforeStops);
      expect(deletes.length, beforeDeletes);
      expect(File(current).existsSync(), true);
      final fresh = await capture.stop();
      expect(fresh!.path, current);
      expect(token.outcome, CaptureCleanupOutcome.transferred);
      // Old output belongs to the legacy caller, not cleanup.
      expect(deletes, isEmpty);
      expect(File(oldPath).existsSync(), true);
      await AudioCapture.deleteQuietly(fresh);
      await AudioCapture.deleteQuietly(File(oldPath));
    },
  );
  test('foreign token cannot stop or delete current capture', () async {
    final otherDriver = _Driver();
    final otherDir = Directory('${dir.path}/other')..createSync();
    final other = AudioCapture(
      driver: otherDriver,
      tempDirProvider: () async => otherDir,
    );
    final foreign = other.acquire()!;
    await foreign.started;
    await capture.start();
    expect(await capture.cleanup(foreign), CaptureCleanupOutcome.mismatch);
    expect(driver.stops, 0);
    expect(driver.open, true);
    expect(deletes, isEmpty);
    await other.dispose();
  });
  test('busy legacy entered start yields no acquisition identity', () async {
    driver.startEntered = Completer<void>();
    driver.startGate = Completer<void>();
    final start = capture.start();
    await driver.startEntered!.future;
    expect(capture.acquire(), null);
    await capture.start(); // Existing legacy idempotence preserved.
    expect(driver.starts, 1);
    driver.startGate!.complete();
    await start;
    expect(capture.acquire(), null);
    final file = await capture.stop();
    await AudioCapture.deleteQuietly(file);
  });
  test(
    'temp failure receipt zero driver stop and stale token after new start',
    () async {
      final failed = AudioCapture(
        driver: driver,
        tempDirProvider: () async => throw StateError('private'),
      );
      final token = failed.acquire()!;
      await expectLater(token.started, throwsStateError);
      expect(await failed.cleanup(token), CaptureCleanupOutcome.noDriverEntry);
      expect(driver.starts, 0);
      expect(driver.stops, 0);
      await failed.dispose();
    },
  );
  test(
    'cleanup before held start release fences acquisition and release delivery',
    () async {
      driver.startEntered = Completer<void>();
      driver.startGate = Completer<void>();
      final token = capture.acquire()!;
      await driver.startEntered!.future;
      final cleanup = capture.cleanup(token);
      final release = capture.stop();
      expect(capture.acquire(), null);
      driver.startGate!.complete();
      await token.started;
      expect(await cleanup, CaptureCleanupOutcome.cleaned);
      expect(await release, null);
      expect(driver.stops, 1);
      expect(deletes.length, 1);
    },
  );
  test(
    'entered external stop then cleanup joins and owns output without delivery',
    () async {
      final token = capture.acquire()!;
      await token.started;
      driver.stopEntered = Completer<void>();
      driver.stopGate = Completer<void>();
      final release = capture.stop();
      await driver.stopEntered!.future;
      final cleanup = capture.cleanup(token);
      driver.stopGate!.complete();
      expect(await cleanup, CaptureCleanupOutcome.cleaned);
      expect(await release, null);
      expect(driver.stops, 1);
      expect(deletes.length, 1);
    },
  );
  test('cap cleanup release race one stop exact file owner', () {
    fakeAsync((async) {
      final capped = AudioCapture(
        driver: driver,
        maxDuration: const Duration(seconds: 1),
        tempDirProvider: () async => _Temp(dir.path),
        deleteFile: (file) async {
          if (file.existsSync()) file.deleteSync();
        },
      );
      final token = capped.acquire()!;
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(driver.stops, 1);
      expect(capped.cleanupPending, false); // Pending output still exists.
      CaptureCleanupOutcome? result;
      File? delivered;
      capped.cleanup(token).then((value) => result = value);
      capped.stop().then((value) => delivered = value);
      async.flushMicrotasks();
      expect(result, CaptureCleanupOutcome.cleaned);
      expect(delivered, null);
      expect(driver.stops, 1);
      expect(File(driver.path!).existsSync(), false);
      capped.dispose();
      async.flushMicrotasks();
    });
  });
  test(
    'dispose failure receipt does not authorize stop on disposed driver',
    () async {
      final token = capture.acquire()!;
      await token.started;
      driver.failStop = true;
      await expectLater(
        capture.dispose(),
        throwsA(isA<CaptureLifecycleException>()),
      );
      expect(driver.disposals, 1);
      expect(driver.open, true);
      expect(token.outcome, CaptureCleanupOutcome.disposalUncertain);
      final stops = driver.stops;
      expect(
        await capture.cleanup(token),
        CaptureCleanupOutcome.disposalUncertain,
      );
      expect(driver.stops, stops);
      driver.failStop = false;
      await capture.dispose();
      expect(token.outcome, CaptureCleanupOutcome.cleaned);
    },
  );
  test('dispose while cleanup held joins before driver release', () async {
    final token = capture.acquire()!;
    await token.started;
    driver.stopEntered = Completer<void>();
    driver.stopGate = Completer<void>();
    final cleanup = capture.cleanup(token);
    await driver.stopEntered!.future;
    final close = capture.dispose();
    var closed = false;
    close.then((_) => closed = true);
    await Future<void>.value();
    expect(closed, false);
    expect(driver.disposals, 0);
    driver.stopGate!.complete();
    await cleanup;
    await close;
    expect(driver.disposals, 1);
    expect(driver.stops, 1);
    expect(capture.cleanupPending, false);
  });
  test(
    'identity exists during entered partial start and cleanup joins failure',
    () async {
      driver.partial = true;
      driver.startEntered = Completer<void>();
      driver.startGate = Completer<void>();
      final token = capture.acquire()!;
      final started = expectLater(
        token.started,
        throwsA(isA<CaptureLifecycleException>()),
      );
      await driver.startEntered!.future;
      final a = capture.cleanup(token), b = capture.cleanup(token);
      expect(b, same(a));
      var done = false;
      a.then((_) => done = true);
      await Future<void>.value();
      expect(done, false);
      expect(driver.stops, 0);
      driver.startGate!.complete();
      await started;
      expect(await a, CaptureCleanupOutcome.cleaned);
      await b;
      expect(done, true);
      expect(driver.stops, 1);
      expect(File(driver.path!).existsSync(), false);
    },
  );
  test(
    'driver disposal error retained separately from complete stop',
    () async {
      final token = capture.acquire()!;
      await token.started;
      driver.failDispose = true;
      await expectLater(
        capture.dispose(),
        throwsA(isA<CaptureLifecycleException>()),
      );
      expect(capture.disposeFailed, true);
      expect(token.outcome, CaptureCleanupOutcome.disposalUncertain);
      final stops = driver.stops;
      expect(
        await capture.cleanup(token),
        CaptureCleanupOutcome.disposalUncertain,
      );
      expect(driver.stops, stops);
      driver.failDispose = false;
      await capture.dispose();
      expect(driver.disposals, 2);
      expect(token.outcome, CaptureCleanupOutcome.cleaned);
    },
  );
  test('pre-entry failure receipt survives later legacy acquisition without effects', () async {
    var fail = true;
    capture = AudioCapture(
      driver: driver,
      tempDirProvider: () async {
        if (fail) throw StateError('private');
        return dir;
      },
    );
    final old = capture.acquire()!;
    await expectLater(old.started, throwsStateError);
    fail = false;
    await capture.start();
    final current = capture.debugPath!;
    expect(await capture.cleanup(old), CaptureCleanupOutcome.noDriverEntry);
    expect(driver.stops, 0);
    expect(driver.open, true);
    final file = await capture.stop();
    expect(file!.path, current);
    await AudioCapture.deleteQuietly(file);
  });
  test(
    'queued cleanup then immediate disposal never stops disposed driver',
    () async {
      final token = capture.acquire()!;
      await token.started;
      final cleanup = capture.cleanup(token);
      final close = capture.dispose();
      expect(await cleanup, CaptureCleanupOutcome.disposalUncertain);
      await close;
      expect(
        driver.stops,
        1,
      ); // Close, not the rejected cleanup, owns this stop.
      expect(driver.disposals, 1);
      expect(token.outcome, CaptureCleanupOutcome.cleaned);
      final before = driver.stops;
      expect(await capture.cleanup(token), CaptureCleanupOutcome.cleaned);
      expect(driver.stops, before);
    },
  );
}
