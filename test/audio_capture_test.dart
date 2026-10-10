import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:local_bluey/services/audio_capture.dart';

class FakeDriver implements RecorderDriver {
  bool recording = false;
  Completer<void>? startGate;
  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  bool startFailsAfterOpen = false;
  bool stopFails = false;
  bool disposeFails = false;
  Completer<void>? disposeGate;
  Completer<String?>? stopGate;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async {
    startCalls++;
    final gate = startGate;
    if (gate != null) await gate.future;
    recording = true;
    if (startFailsAfterOpen) throw StateError('private native start detail');
  }

  @override
  Future<String?> stop() async {
    stopCalls++;
    final result = stopGate == null
        ? '/tmp/fake_capture.m4a'
        : await stopGate!.future;
    if (stopFails) throw StateError('private native stop detail');
    recording = false;
    return result;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (disposeGate != null) await disposeGate!.future;
    if (disposeFails) throw StateError('private native disposal detail');
  }
}

class EmptyTempDirectory implements Directory {
  @override
  String get path => '/tmp/capture-test';
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  AudioCapture makeCapture(FakeDriver driver) => AudioCapture(
    driver: driver,
    tempDirProvider: () async => EmptyTempDirectory(),
  );

  test(
    'partial start owns candidate, safe typed error, successful cleanup only',
    () async {
      final driver = FakeDriver()..startFailsAfterOpen = true;
      final capture = makeCapture(driver);
      await expectLater(
        capture.start(),
        throwsA(isA<CaptureLifecycleException>()),
      );
      expect(driver.recording, true);
      expect(capture.cleanupPending, true);
      expect(capture.isRecording, false);
      final path = capture.debugPath;
      await expectLater(capture.start(), throwsStateError);
      expect(driver.startCalls, 1);
      expect(capture.debugPath, path);
      await capture.stop();
      expect(driver.stopCalls, 1);
      expect(capture.cleanupPending, false);
      driver.startFailsAfterOpen = false;
      await capture.start();
      await capture.dispose();
    },
  );

  test(
    'gated entered partial start joins stop and all failed stop callers',
    () async {
      final driver = FakeDriver()
        ..startGate = Completer<void>()
        ..startFailsAfterOpen = true
        ..stopGate = Completer<String?>();
      final capture = makeCapture(driver);
      final starting = expectLater(
        capture.start(),
        throwsA(isA<CaptureLifecycleException>()),
      );
      final first = expectLater(
        capture.stop(),
        throwsA(isA<CaptureLifecycleException>()),
      );
      final second = expectLater(
        capture.stop(),
        throwsA(isA<CaptureLifecycleException>()),
      );
      expect(driver.stopCalls, 0);
      driver.startGate!.complete();
      await starting;
      await Future<void>.delayed(Duration.zero);
      expect(driver.stopCalls, 1);
      driver.stopGate!.completeError(StateError('private stop detail'));
      await Future.wait([first, second]);
      expect(driver.recording, true);
      expect(capture.cleanupPending, true);
      await expectLater(capture.start(), throwsStateError);
      driver.stopGate = null;
      driver.stopFails = true;
      await expectLater(
        capture.stop(),
        throwsA(isA<CaptureLifecycleException>()),
      );
      expect(capture.cleanupPending, true);
      driver.stopFails = false;
      await capture.stop();
      expect(capture.cleanupPending, false);
      await capture.dispose();
    },
  );

  test('dispose joins partial start and attempts driver disposal after failed stop', () async {
    final driver = FakeDriver()
      ..startGate = Completer<void>()
      ..startFailsAfterOpen = true
      ..stopFails = true;
    final capture = makeCapture(driver);
    final starting = expectLater(
      capture.start(),
      throwsA(isA<CaptureLifecycleException>()),
    );
    final closeA = capture.dispose();
    final closeB = capture.dispose();
    expect(identical(closeA, closeB), true);
    final closing = expectLater(
      closeA,
      throwsA(isA<CaptureLifecycleException>()),
    );
    driver.startGate!.complete();
    await starting;
    await closing;
    expect(driver.stopCalls, 1);
    expect(driver.disposeCalls, 1);
    expect(driver.recording, true); // Dispose success is not proof of stop.
    expect(capture.cleanupPending, true);
    await expectLater(
      capture.dispose(),
      throwsA(isA<CaptureLifecycleException>()),
    );
    expect(
      driver.disposeCalls,
      1,
    ); // Completed driver disposal stays exact-once.
    driver.stopFails = false;
    await capture.dispose();
    expect(capture.cleanupPending, false);
    expect(driver.disposeCalls, 1);
    await expectLater(capture.start(), throwsStateError);
  });

  test(
    'dispose failure retained safe and explicitly retryable once per attempt',
    () async {
      final driver = FakeDriver()
        ..disposeFails = true
        ..disposeGate = Completer<void>();
      final capture = makeCapture(driver);
      await capture.start();
      final a = capture.dispose();
      final b = capture.dispose();
      expect(identical(a, b), true);
      final failure = expectLater(
        a,
        throwsA(
          isA<CaptureLifecycleException>().having(
            (e) => e.message,
            'generic',
            isNot(contains('private')),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      driver.disposeGate!.complete();
      await failure;
      expect(capture.disposeFailed, true);
      expect(capture.cleanupPending, true);
      expect(driver.recording, false);
      await expectLater(capture.start(), throwsStateError);
      driver.disposeFails = false;
      await capture.dispose();
      expect(capture.disposeFailed, false);
      expect(capture.cleanupPending, false);
      await capture.dispose();
      expect(driver.disposeCalls, 2);
    },
  );

  test(
    'entered release joined by dispose does not publish post-close file',
    () async {
      final dir = await Directory.systemTemp.createTemp('capture-close-');
      final file = await File('${dir.path}/finished.m4a')
          .writeAsString('synthetic');
      final driver = FakeDriver()..stopGate = Completer<String?>();
      final capture = makeCapture(driver);
      await capture.start();
      final release = capture.stop();
      final close = capture.dispose();
      driver.stopGate!.complete(file.path);
      expect(await release, null);
      await close;
      expect(driver.stopCalls, 1);
      expect(driver.disposeCalls, 1);
      expect(await file.exists(), false); // Synthetic temp file only.
      await dir.delete();
    },
  );

  test('successful-null recovery retains exact candidate on deletion failure until explicit retry', () async {
    final dir = await Directory.systemTemp.createTemp('capture-delete-');
    final driver = FakeDriver()
      ..startFailsAfterOpen = true
      ..stopGate = Completer<String?>();
    final deleted = <String>[];
    var failDelete = true;
    final capture = AudioCapture(
      driver: driver,
      tempDirProvider: () async => dir,
      deleteFile: (file) async {
        deleted.add(file.path);
        if (failDelete) throw FileSystemException('private path');
        if (await file.exists()) await file.delete();
      },
    );
    await expectLater(
      capture.start(),
      throwsA(isA<CaptureLifecycleException>()),
    );
    final candidate = await File(capture.debugPath!).writeAsString('synthetic');
    final recovery = expectLater(
      capture.stop(),
      throwsA(isA<CaptureLifecycleException>()),
    );
    driver.stopGate!.complete(null);
    await recovery;
    expect(capture.cleanupPending, true);
    expect(await candidate.exists(), true);
    await expectLater(capture.start(), throwsStateError);
    expect(deleted, [candidate.path]);
    failDelete = false;
    expect(await capture.stop(), null);
    expect(driver.stopCalls, 1); // File-only retry does not repeat native stop.
    expect(deleted, [candidate.path, candidate.path]);
    expect(capture.cleanupPending, false);
    expect(await candidate.exists(), false);
    await capture.dispose();
    await dir.delete();
  });

  test(
    'closing delete failure retains file and still attempts driver dispose',
    () async {
      final driver = FakeDriver();
      var failDelete = true;
      final capture = AudioCapture(
        driver: driver,
        tempDirProvider: () async => EmptyTempDirectory(),
        deleteFile: (_) async {
          if (failDelete) throw StateError('delete');
        },
      );
      await capture.start();
      await expectLater(
        capture.dispose(),
        throwsA(isA<CaptureLifecycleException>()),
      );
      expect(capture.cleanupPending, true);
      expect(driver.disposeCalls, 1);
      failDelete = false;
      await capture.dispose();
      expect(capture.cleanupPending, false);
      expect(driver.disposeCalls, 1);
      expect(driver.stopCalls, 1);
    },
  );

  test('temp failure before driver entry is not native uncertainty', () async {
    final driver = FakeDriver();
    var fail = true;
    final capture = AudioCapture(
      driver: driver,
      tempDirProvider: () async {
        if (fail) throw StateError('temp directory unavailable');
        return EmptyTempDirectory();
      },
    );
    await expectLater(capture.start(), throwsStateError);
    expect(driver.startCalls, 0);
    expect(capture.cleanupPending, false);
    expect(await capture.stop(), null);
    expect(driver.stopCalls, 0);
    fail = false;
    await capture.start();
    await capture.dispose();
  });

  test(
    'successful current driver null cleanup clears partial-start uncertainty',
    () async {
      final driver = FakeDriver()
        ..startFailsAfterOpen = true
        ..stopGate = Completer<String?>();
      final capture = makeCapture(driver);
      await expectLater(
        capture.start(),
        throwsA(isA<CaptureLifecycleException>()),
      );
      final stopping = capture.stop();
      expect(capture.cleanupPending, true);
      driver.stopGate!.complete(null);
      expect(await stopping, null);
      expect(driver.stopCalls, 1);
      expect(capture.cleanupPending, false);
      expect(await capture.stop(), null);
      expect(driver.stopCalls, 1); // Wrapper null itself did not do cleanup.
      await capture.dispose();
    },
  );

  test(
    'stop during an in-flight start still stops the recorder (#117)',
    () async {
      final driver = FakeDriver()..startGate = Completer<void>();
      final dir = await Directory.systemTemp.createTemp('cap');
      final capture = AudioCapture(
        driver: driver,
        tempDirProvider: () async => dir,
      );
      final startFuture = capture.start();
      // Release the hold before start() finished: stop must wait, then stop.
      final stopFuture = capture.stop();
      driver.startGate!.complete();
      await startFuture;
      final file = await stopFuture;
      expect(file, isNotNull);
      expect(driver.recording, isFalse);
    },
  );

  test('max duration auto-stops and preserves the file (#117)', () async {
    final driver = FakeDriver();
    final dir = await Directory.systemTemp.createTemp('cap');
    final capture = AudioCapture(
      driver: driver,
      maxDuration: const Duration(milliseconds: 50),
      tempDirProvider: () async => dir,
    );
    await capture.start();
    expect(driver.recording, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(driver.recording, isFalse);
    // The caller's stop() still receives the utterance.
    final file = await capture.stop();
    expect(file, isNotNull);
  });

  test('cap/release joins one stop and consumes its file once (#246)', () {
    fakeAsync((time) {
      final driver = FakeDriver()..stopGate = Completer<String?>();
      final capture = AudioCapture(
        driver: driver,
        maxDuration: const Duration(seconds: 1),
        tempDirProvider: () async => EmptyTempDirectory(),
        deleteFile: (_) async {},
      );
      capture.start();
      time.flushMicrotasks();
      expect(capture.isRecording, isTrue);
      time.elapse(const Duration(seconds: 1));
      expect(driver.stopCalls, 1);
      File? first;
      File? second;
      var finished = false;
      capture.stop().then((file) {
        first = file;
        finished = true;
      });
      capture.stop().then((file) => second = file);
      time.flushMicrotasks();
      expect(finished, isFalse);
      var rejected = false;
      capture.start().catchError((Object error) {
        rejected = error is StateError;
      });
      time.flushMicrotasks();
      expect(rejected, isTrue);
      expect(driver.startCalls, 1);
      driver.stopGate!.complete('/tmp/capped-session.m4a');
      time.flushMicrotasks();
      expect(first?.path, '/tmp/capped-session.m4a');
      expect(second, isNull);
      File? later;
      capture.stop().then((file) => later = file);
      time.flushMicrotasks();
      expect(later, isNull);
      driver.stopGate = null;
      capture.start();
      time.flushMicrotasks();
      expect(driver.startCalls, 2);
      capture.stop().then((file) => later = file);
      time.flushMicrotasks();
      expect(later?.path, '/tmp/fake_capture.m4a');
      capture.dispose();
      time.flushMicrotasks();
    });
  });

  test('failed capped stop is reported on release and recovers (#246)', () {
    fakeAsync((time) {
      final driver = FakeDriver()..stopGate = Completer<String?>();
      final capture = AudioCapture(
        driver: driver,
        maxDuration: const Duration(seconds: 1),
        tempDirProvider: () async => EmptyTempDirectory(),
        deleteFile: (_) async {},
      );
      capture.start();
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 1));
      driver.stopGate!.completeError(StateError('native stop failed'));
      time.flushMicrotasks(); // Timer must not produce an unhandled error.
      Object? error;
      capture.stop().catchError((Object e) {
        error = e;
        return null;
      });
      time.flushMicrotasks();
      expect(error, isA<StateError>());
      driver.stopGate = null;
      var blocked = false;
      capture.start().catchError((Object _) {
        blocked = true;
      });
      time.flushMicrotasks();
      expect(blocked, true);
      expect(driver.startCalls, 1);
      capture.stop(); // Explicit current successful driver cleanup resolves uncertainty.
      time.flushMicrotasks();
      capture.start();
      time.flushMicrotasks();
      expect(driver.startCalls, 2);
      File? file;
      capture.stop().then((f) => file = f);
      time.flushMicrotasks();
      expect(file, isNotNull);
      capture.dispose();
      time.flushMicrotasks();
    });
  });

  test('dispose during start waits and closes the microphone (#246)', () async {
    final driver = FakeDriver()..startGate = Completer<void>();
    final capture = AudioCapture(
      driver: driver,
      tempDirProvider: () async => EmptyTempDirectory(),
    );
    final starting = capture.start();
    final disposing = capture.dispose();
    driver.startGate!.complete();
    await starting;
    await disposing;
    expect(driver.stopCalls, 1);
    expect(driver.recording, isFalse);
    await expectLater(capture.start(), throwsStateError);
  });

  test('start is idempotent while recording (#117)', () async {
    final driver = FakeDriver();
    final dir = await Directory.systemTemp.createTemp('cap');
    final capture = AudioCapture(
      driver: driver,
      tempDirProvider: () async => dir,
    );
    await capture.start();
    await capture.start();
    expect(driver.startCalls, 1);
    await capture.stop();
  });

  test('sweep deletes stale bluey_hold files only (#116)', () async {
    final dir = await Directory.systemTemp.createTemp('cap');
    final stale = await File('${dir.path}/bluey_hold_123.m4a').create();
    final keep = await File('${dir.path}/other.txt').create();
    await AudioCapture.sweepStaleRecordings(tempDir: dir);
    expect(await stale.exists(), isFalse);
    expect(await keep.exists(), isTrue);
  });
}
