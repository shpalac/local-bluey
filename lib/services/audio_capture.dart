import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Thin wrapper over the platform recorder so the capture state machine is
/// testable without a microphone (#117).
abstract class RecorderDriver {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<String?> stop();
  Future<void> dispose();
}

class AudioRecorderDriver implements RecorderDriver {
  AudioRecorderDriver([this.recorder]);
  final AudioRecorder? recorder;
  AudioRecorder? _lazy;
  AudioRecorder get _r => recorder ?? (_lazy ??= AudioRecorder());

  @override
  Future<bool> hasPermission() => _r.hasPermission();
  @override
  Future<void> start(String path) => _r.start(
    const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
    path: path,
  );
  @override
  Future<String?> stop() => _r.stop();
  @override
  Future<void> dispose() => _r.dispose();
}

/// Hold-to-talk audio capture. Transcription is pluggable: send the file to
/// any OpenAI-compatible /audio/transcriptions endpoint, or swap in a local
/// whisper.cpp binding later.
///
/// Lifecycle fixes (#117): start() is idempotent, stop() waits for an
/// in-flight start() before stopping (start/stop race left the mic open),
/// and a recording can never exceed [maxDuration] - a stuck caller can no
/// longer record forever.
class AudioCapture {
  AudioCapture({
    RecorderDriver? driver,
    Duration? maxDuration,
    Future<Directory> Function()? tempDirProvider,
  }) : _driver = driver ?? AudioRecorderDriver(),
       maxDuration = maxDuration ?? const Duration(minutes: 2),
       _tempDirProvider = tempDirProvider ?? getTemporaryDirectory;

  final RecorderDriver _driver;
  final Future<Directory> Function() _tempDirProvider;

  /// Hard cap on one hold-to-talk recording (#117).
  final Duration maxDuration;

  bool _recording = false;
  Future<void>? _startOp;
  Timer? _maxTimer;
  String? _path;
  File? _pendingFile;

  bool get isRecording => _recording;

  Future<bool> hasPermission() => _driver.hasPermission();

  Future<void> start() async {
    if (_recording || _startOp != null) return;
    final op = _start();
    _startOp = op;
    try {
      await op;
    } finally {
      _startOp = null;
    }
  }

  Future<void> _start() async {
    final dir = await _tempDirProvider();
    await sweepStaleRecordings(tempDir: dir);
    _path =
        '${dir.path}/bluey_hold_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _driver.start(_path!);
    _recording = true;
    _maxTimer = Timer(maxDuration, () {
      unawaited(_autoStop());
    });
  }

  /// Max-duration cap: stops the recorder but keeps the file so the
  /// caller's [stop] still delivers the utterance (#117).
  Future<void> _autoStop() async {
    if (!_recording) return;
    _recording = false;
    final path = await _driver.stop();
    if (path != null) _pendingFile = File(path);
  }

  /// Stops and returns the recorded file, or null if nothing was captured.
  /// Waits for an in-flight [start] first so a fast tap cannot leave the
  /// microphone recording (#117).
  Future<File?> stop() async {
    _maxTimer?.cancel();
    _maxTimer = null;
    final op = _startOp;
    if (op != null) {
      try {
        await op;
      } catch (_) {
        // Start failed; nothing to stop.
      }
    }
    if (!_recording) {
      final pending = _pendingFile;
      _pendingFile = null;
      return pending;
    }
    _recording = false;
    final path = await _driver.stop();
    if (path == null) return null;
    return File(path);
  }

  /// Deletes leftover `bluey_hold_*.m4a` captures from previous sessions
  /// (#116). Called on every start; also callable directly.
  static Future<void> sweepStaleRecordings({Directory? tempDir}) async {
    final dir = tempDir ?? await getTemporaryDirectory();
    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('bluey_hold_')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Deletes a finished capture file, ignoring errors (#116).
  static Future<void> deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _maxTimer?.cancel();
    _maxTimer = null;
    await _driver.dispose();
  }

  @visibleForTesting
  String? get debugPath => _path;
}
