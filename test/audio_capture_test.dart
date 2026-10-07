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
  Completer<String?>? stopGate;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async {
    startCalls++;
    final gate = startGate;
    if (gate != null) await gate.future;
    recording = true;
  }

  @override
  Future<String?> stop() async {
    stopCalls++;
    final result = stopGate == null
        ? '/tmp/fake_capture.m4a'
        : await stopGate!.future;
    recording = false;
    return result;
  }

  @override
  Future<void> dispose() async {}
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
