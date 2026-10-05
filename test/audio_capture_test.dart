import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/audio_capture.dart';

class FakeDriver implements RecorderDriver {
  bool recording = false;
  Completer<void>? startGate;
  int startCalls = 0;

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
    recording = false;
    return '/tmp/fake_capture.m4a';
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('stop during an in-flight start still stops the recorder (#117)',
      () async {
    final driver = FakeDriver()..startGate = Completer<void>();
    final dir = await Directory.systemTemp.createTemp('cap');
    final capture = AudioCapture(driver: driver, tempDirProvider: () async => dir);
    final startFuture = capture.start();
    // Release the hold before start() finished: stop must wait, then stop.
    final stopFuture = capture.stop();
    driver.startGate!.complete();
    await startFuture;
    final file = await stopFuture;
    expect(file, isNotNull);
    expect(driver.recording, isFalse);
  });

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

  test('start is idempotent while recording (#117)', () async {
    final driver = FakeDriver();
    final dir = await Directory.systemTemp.createTemp('cap');
    final capture = AudioCapture(driver: driver, tempDirProvider: () async => dir);
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
