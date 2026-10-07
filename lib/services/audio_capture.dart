import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Thin wrapper over the platform recorder so the capture state machine is
/// testable without a microphone (#117).
abstract class RecorderDriver {
  /// Whether mic permission is currently granted (never prompts).
  Future<bool> hasPermission();

  /// Starts recording into [path].
  Future<void> start(String path);

  /// Stops and returns the recorded path, or null when nothing recorded.
  Future<String?> stop();

  /// Releases the recorder.
  Future<void> dispose();
}

/// Production [RecorderDriver] on the record plugin.
class AudioRecorderDriver implements RecorderDriver {
  AudioRecorderDriver([this.recorder]);

  /// Test seam: inject a fake recorder.
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
  Future<void>? _stopOp;
  Object? _stopError;
  int _session = 0;
  bool _disposed = false;

  /// Whether a capture is currently open.
  bool get isRecording => _recording;

  /// Whether mic permission is granted; never prompts (#174).
  Future<bool> hasPermission() => _driver.hasPermission();

  /// Starts a capture into a fresh temp .m4a (AAC-LC 16 kHz).
  Future<void> start() async {
    if (_disposed) throw StateError('Audio capture is disposed');
    if (_stopOp != null || _pendingFile != null || _stopError != null) {
      throw StateError('Release the previous capture before starting another');
    }
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
    final session = ++_session;
    final dir = await _tempDirProvider();
    await sweepStaleRecordings(tempDir: dir);
    _path =
        '${dir.path}/bluey_hold_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _driver.start(_path!);
    _recording = true;
    if (_disposed || session != _session) return;
    _maxTimer = Timer(maxDuration, () {
      _beginStop();
    });
  }

  // Both the cap and release share one native stop. Errors are retained for
  // the release caller, never thrown from an unawaited timer future.
  void _beginStop() {
    if (!_recording || _stopOp != null) return;
    _maxTimer?.cancel();
    _maxTimer = null;
    _recording = false;
    final session = _session;
    _stopOp = _finishStop(session);
  }

  Future<void> _finishStop(int session) async {
    try {
      final path = await _driver.stop();
      if (!_disposed && session == _session && path != null) {
        _pendingFile = File(path);
      }
    } catch (error) {
      if (!_disposed && session == _session) _stopError = error;
    }
  }

  /// Stops and delivers this session's file exactly once, joining an in-flight
  /// start or capped stop. A new start is rejected until release consumes the
  /// previous session, so one hold cannot receive another hold's recording.
  Future<File?> stop() async {
    final startOp = _startOp;
    if (startOp != null) {
      try {
        await startOp;
      } catch (_) {
        // Start failed; nothing to stop.
      }
    }
    _beginStop();
    final stopOp = _stopOp;
    if (stopOp != null) await stopOp;
    // Only the first release owns the completed session. Another release
    // must not consume state created by a subsequent start.
    if (!identical(stopOp, _stopOp)) return null;
    _stopOp = null;
    final error = _stopError;
    _stopError = null;
    if (error != null) throw error;
    final pending = _pendingFile;
    _pendingFile = null;
    return pending;
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

  /// Stops any open capture and releases the driver.
  Future<void> dispose() async {
    _maxTimer?.cancel();
    _maxTimer = null;
    if (_disposed) return;
    _disposed = true;
    try {
      await stop();
    } finally {
      _session++;
      _pendingFile = null;
      _stopError = null;
      await _driver.dispose();
    }
  }

  @visibleForTesting
  /// Test seam: the path of the current/last capture.
  String? get debugPath => _path;
}
