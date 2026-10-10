import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Safe capture lifecycle uncertainty without native details.
class CaptureLifecycleException extends StateError {
  /// Creates a generic retained capture failure.
  CaptureLifecycleException()
    : super('Audio capture cleanup could not be verified.');
}

/// Thin wrapper over the platform recorder so the capture state machine is
/// testable without a microphone (#117).
abstract class RecorderDriver {
  /// Whether mic permission is currently granted (never prompts).
  Future<bool> hasPermission();

  /// Starts recording into [path].
  Future<void> start(String path);

  /// Stops and returns the recorded path, or null when nothing recorded.
  /// Success (including null) confirms stop under this injected contract.
  /// Failure may leave capture open. Plugin behavior needs native validation.
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
    Future<void> Function(File)? deleteFile,
  }) : _driver = driver ?? AudioRecorderDriver(),
       maxDuration = maxDuration ?? const Duration(minutes: 2),
       _tempDirProvider = tempDirProvider ?? getTemporaryDirectory,
       _deleteFile = deleteFile ?? _deleteOwnedFile;

  final RecorderDriver _driver;
  final Future<Directory> Function() _tempDirProvider;
  final Future<void> Function(File) _deleteFile;
  final Set<String> _cleanupFiles = {};

  /// Hard cap on one hold-to-talk recording (#117).
  final Duration maxDuration;

  bool _recording = false;
  bool _candidate = false;
  bool _uncertain = false;
  bool _disposeFailed = false;
  bool _driverDisposed = false;
  Future<void>? _disposeOp;
  Future<void>? _startOp;
  Timer? _maxTimer;
  String? _path;
  File? _pendingFile;
  Future<CaptureLifecycleException?>? _stopOp;
  Object? _stopError;
  int _session = 0;
  bool _disposed = false;

  /// Whether an entered capture or failed driver cleanup is still owned.
  /// A successful driver disposal alone does not prove capture stop.
  bool get cleanupPending =>
      _candidate || _uncertain || _disposeFailed || _cleanupFiles.isNotEmpty;

  /// Whether the last driver disposal attempt failed.
  bool get disposeFailed => _disposeFailed;

  /// Whether a capture is currently open.
  bool get isRecording => _recording;

  /// Whether mic permission is granted; never prompts (#174).
  Future<bool> hasPermission() => _driver.hasPermission();

  /// Starts a capture into a fresh temp .m4a (AAC-LC 16 kHz).
  Future<void> start() async {
    if (_disposed) throw StateError('Audio capture is disposed');
    if (_uncertain ||
        _cleanupFiles.isNotEmpty ||
        _stopOp != null ||
        _pendingFile != null ||
        _stopError != null) {
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
    _candidate = true;
    try {
      await _driver.start(_path!);
    } catch (_) {
      _uncertain = true;
      throw CaptureLifecycleException();
    }
    _recording = true;
    if (_disposed || session != _session) return;
    _maxTimer = Timer(maxDuration, () {
      _beginStop();
    });
  }

  // Both the cap and release share one native stop. Errors are retained for
  // the release caller, never thrown from an unawaited timer future.
  void _beginStop() {
    if ((!_recording && !_candidate && _cleanupFiles.isEmpty) ||
        _stopOp != null) {
      return;
    }
    _maxTimer?.cancel();
    _maxTimer = null;
    _recording = false;
    final session = _session;
    _stopOp = _finishStop(session);
  }

  Future<CaptureLifecycleException?> _finishStop(int session) async {
    try {
      if (_candidate) {
        final wasUncertain = _uncertain;
        final path = await _driver.stop();
        if (session == _session) {
          _candidate = false;
          _uncertain = false;
          if (path != null) _pendingFile = File(path);
          // Successful-null cleanup still owns the known entered candidate.
          // A failed candidate is never silently left for a fresh-start sweep.
          if (_path != null &&
              (path == null || (wasUncertain && path != _path))) {
            _cleanupFiles.add(_path!);
          }
        }
      }
      await _cleanupOwnedFiles();
      if (session == _session) _stopError = null;
    } catch (_) {
      if (session == _session) {
        if (_candidate) _uncertain = true;
        _stopError = CaptureLifecycleException();
      }
      return CaptureLifecycleException();
    }
    return null;
  }

  static Future<void> _deleteOwnedFile(File file) async {
    if (await file.exists()) await file.delete();
  }

  Future<void> _cleanupOwnedFiles() async {
    for (final path in _cleanupFiles.toList()) {
      await _deleteFile(File(path));
      // Remove only after successful file operation.
      _cleanupFiles.remove(path);
    }
  }

  /// Stops and delivers this session's file exactly once, joining an in-flight
  /// start or capped stop. A new start is rejected until release consumes the
  /// previous session, so one hold cannot receive another hold's recording.
  Future<File?> stop() => _stop();

  Future<File?> _stop({bool closing = false}) async {
    final startOp = _startOp;
    if (startOp != null) {
      try {
        await startOp;
      } catch (_) {
        // A failed entered start can still own an open driver candidate.
      }
    }
    _beginStop();
    final stopOp = _stopOp;
    final failure = stopOp == null ? null : await stopOp;
    // Only the first release owns the completed session. Another release
    // must not consume state created by a subsequent start.
    if (failure != null) {
      if (identical(stopOp, _stopOp)) _stopOp = null;
      throw failure; // Every joiner observes failure, never false idle/null.
    }
    if (_disposed && !closing) return null; // Closing owns post-close files.
    if (!identical(stopOp, _stopOp)) return null;
    _stopOp = null;
    final error = _stopError;
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

  /// Joins entered capture effects and always attempts driver release.
  /// Failure is typed, retained, and explicitly retryable. Successful driver
  /// release alone is never evidence that a failed stop succeeded.
  Future<void> dispose() {
    final pending = _disposeOp;
    if (pending != null) return pending;
    if (_disposed && !_disposeFailed && !_uncertain && _cleanupFiles.isEmpty) {
      return Future<void>.value();
    }
    _disposed = true;
    final op = _disposeCapture();
    _disposeOp = op;
    op.then(
      (_) {
        _disposeOp = null;
      },
      onError: (Object _, StackTrace _) {
        _disposeOp = null;
      },
    );
    return op;
  }

  Future<void> _disposeCapture() async {
    _maxTimer?.cancel();
    _maxTimer = null;
    var failed = false;
    try {
      final file = await _stop(closing: true);
      if (file != null) _cleanupFiles.add(file.path);
      await _cleanupOwnedFiles();
    } catch (_) {
      failed = true;
    }
    if (!_driverDisposed) {
      try {
        await _driver.dispose();
        _driverDisposed = true;
        _disposeFailed = false;
      } catch (_) {
        _disposeFailed = true;
        failed = true;
      }
    }
    if (failed) throw CaptureLifecycleException();
  }

  @visibleForTesting
  /// Test seam: the path of the current/last capture.
  String? get debugPath => _path;
}
