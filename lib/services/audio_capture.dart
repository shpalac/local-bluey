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

/// Token-scoped Dart cleanup evidence, never native readiness or key reuse.
enum CaptureCleanupOutcome {
  /// Acquisition failed before any driver start entry.
  noDriverEntry,

  /// This token's driver candidate and owned files were cleaned.
  cleaned,

  /// A legacy release consumed this token's output. Reporting only.
  transferred,

  /// The instance closed without a confirmed complete cleanup receipt.
  disposalUncertain,

  /// The identity does not own this instance's current candidate.
  mismatch,
}

/// Token release result. A file is transferred to exactly one caller.
/// A null file has an explicit token-scoped outcome, never generic idle proof.
class CaptureRelease {
  CaptureRelease._(this.file, this.outcome);

  /// Exact owned output, or null when no output was transferred to this call.
  final File? file;

  /// Positive terminal evidence for this identity, not native/key readiness.
  final CaptureCleanupOutcome outcome;
}

/// Opaque attempted acquisition. Retained even when [started] rejects.
/// Evidence lives on this handle, not an unbounded capture history.
class CaptureAcquisition {
  CaptureAcquisition._(this._owner);
  final AudioCapture _owner;
  late final Future<void> _started;
  Future<CaptureCleanupOutcome>? _cleanup;
  Future<File?>? _release;
  bool _fileClaimed = false;
  CaptureCleanupOutcome? _outcome;
  bool _driverEntered = false, _stopConfirmed = false;

  /// Actual attempted start completion; failures must be observed by caller.
  Future<void> get started => _started;

  /// Positive terminal evidence, null while this resource remains unresolved.
  /// Transfer does not authorize reuse by a key owner.
  CaptureCleanupOutcome? get outcome => _outcome;
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
  Future<void>? _cleanupOp;
  CaptureAcquisition? _acquisition;
  Future<CaptureCleanupOutcome>? _sessionCleanup;
  Future<void>? _sessionRelease;

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
  Future<void> start() => _startWithIdentity(null);

  /// Attempts exclusive opt-in acquisition; busy legacy work yields no token.
  /// The handle exists before temp/driver awaits and survives start failure.
  CaptureAcquisition? acquire() {
    if (_disposed ||
        _recording ||
        _startOp != null ||
        _sessionCleanup != null ||
        _sessionRelease != null ||
        _uncertain ||
        _cleanupFiles.isNotEmpty ||
        _stopOp != null ||
        _pendingFile != null ||
        _stopError != null) {
      return null;
    }
    final identity = CaptureAcquisition._(this);
    identity._started = _startWithIdentity(identity);
    return identity;
  }

  Future<void> _startWithIdentity(CaptureAcquisition? identity) async {
    if (_disposed) throw StateError('Audio capture is disposed');
    if (_sessionCleanup != null ||
        _sessionRelease != null ||
        _uncertain ||
        _cleanupFiles.isNotEmpty ||
        _stopOp != null ||
        _pendingFile != null ||
        _stopError != null) {
      throw StateError('Release the previous capture before starting another');
    }
    if (_recording || _startOp != null) return;
    _acquisition = identity;
    final op = _start();
    _startOp = op;
    try {
      await op;
    } catch (_) {
      if (identity != null && !identity._driverEntered) {
        identity._outcome = CaptureCleanupOutcome.noDriverEntry;
      }
      rethrow;
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
    _acquisition?._driverEntered = true;
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
          _acquisition?._stopConfirmed = true;
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

  Future<void> _cleanupOwnedFiles() {
    final pending = _cleanupOp;
    if (pending != null) return pending;
    final op = _deleteCleanupFiles();
    _cleanupOp = op;
    op.then(
      (_) {
        _cleanupOp = null;
      },
      onError: (Object _, StackTrace _) {
        _cleanupOp = null;
      },
    );
    return op;
  }

  Future<void> _deleteCleanupFiles() async {
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

  Future<File?> _stop({
    bool closing = false,
    bool recovering = false,
    bool releasing = false,
  }) async {
    final release = _sessionRelease;
    if (release != null && !releasing && !recovering && !closing) {
      await release;
      return null;
    }
    final cleanup = _sessionCleanup;
    if (cleanup != null && !recovering && !closing) {
      await cleanup;
      return null; // Explicit recovery owns output, never delivers it.
    }
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
    if (_sessionRelease != null && !releasing && !recovering && !closing) {
      await _sessionRelease;
      return null;
    }
    if (_sessionCleanup != null && !recovering && !closing) {
      await _sessionCleanup;
      return null;
    }
    if (_disposed && !closing && !recovering) {
      return null;
    } // Closing owns post-close files.
    if (!identical(stopOp, _stopOp)) return null;
    _stopOp = null;
    final error = _stopError;
    if (error != null) throw error;
    final pending = _pendingFile;
    _pendingFile = null;
    final identity = _acquisition;
    if (!recovering && !closing && identity != null) {
      if (pending != null) {
        identity._outcome = CaptureCleanupOutcome.transferred;
      } else if (identity._stopConfirmed && _cleanupFiles.isEmpty) {
        identity._outcome = CaptureCleanupOutcome.cleaned;
      }
    }
    return pending;
  }

  /// Opt-in token-scoped normal release. Concurrent callers join one stop,
  /// but only one receives the file. Cleanup selected before consumption owns
  /// output without delivery. Terminal/foreign tokens have no resource effect.
  Future<CaptureRelease> release(CaptureAcquisition identity) {
    if (!identical(identity._owner, this)) {
      return Future.value(
        CaptureRelease._(null, CaptureCleanupOutcome.mismatch),
      );
    }
    final pending = identity._release;
    if (pending != null) return _claimRelease(identity, pending);
    final terminal = identity._outcome;
    if (terminal != null) return Future.value(CaptureRelease._(null, terminal));
    if (!identical(identity, _acquisition)) {
      return Future.value(
        CaptureRelease._(null, CaptureCleanupOutcome.mismatch),
      );
    }
    if (_disposed || _driverDisposed) {
      return Future.value(
        CaptureRelease._(null, CaptureCleanupOutcome.disposalUncertain),
      );
    }
    final op = Future<File?>.microtask(() => _releaseAcquisition(identity));
    identity._release = op;
    final fence = op.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _sessionRelease = fence;
    fence.then((_) {
      if (identical(identity._release, op)) identity._release = null;
      if (identical(_sessionRelease, fence)) _sessionRelease = null;
    });
    return _claimRelease(identity, op);
  }

  Future<CaptureRelease> _claimRelease(
    CaptureAcquisition identity,
    Future<File?> op,
  ) async {
    final file = await op;
    final claimed = identity._fileClaimed;
    if (file != null && !claimed) identity._fileClaimed = true;
    return CaptureRelease._(
      claimed ? null : file,
      identity._outcome ?? CaptureCleanupOutcome.disposalUncertain,
    );
  }

  Future<File?> _releaseAcquisition(CaptureAcquisition identity) async {
    try {
      await identity.started;
    } catch (_) {
      if (identity._driverEntered) throw CaptureLifecycleException();
    }
    if (identity._outcome != null) return null;
    if (!identical(identity, _acquisition) || _disposed || _driverDisposed) {
      return null;
    }
    return _stop(releasing: true);
  }

  /// Explicit token-scoped cleanup with no file delivery. Concurrent calls
  /// return the same completion through stop and exact owned-file deletion.
  /// Foreign/stale tokens never touch a newer capture. Typed errors retain
  /// ownership for another explicit attempt. No stop on a disposed driver.
  Future<CaptureCleanupOutcome> cleanup(CaptureAcquisition identity) {
    if (!identical(identity._owner, this)) {
      return Future.value(CaptureCleanupOutcome.mismatch);
    }
    final pending = identity._cleanup;
    if (pending != null) return pending;
    final terminal = identity._outcome;
    if (terminal != null) return Future.value(terminal);
    if (!identical(identity, _acquisition)) {
      return Future.value(CaptureCleanupOutcome.mismatch);
    }
    if (_disposed || _driverDisposed) {
      return Future.value(CaptureCleanupOutcome.disposalUncertain);
    }
    // Install fence before asynchronous entry, including legacy acquisition.
    final op = Future<CaptureCleanupOutcome>.microtask(
      () => _cleanupAcquisition(identity),
    );
    identity._cleanup = op;
    _sessionCleanup = op;
    void settled() {
      if (identical(identity._cleanup, op)) identity._cleanup = null;
      if (identical(_sessionCleanup, op)) _sessionCleanup = null;
    }

    op.then((_) => settled(), onError: (Object _, StackTrace _) => settled());
    return op;
  }

  Future<CaptureCleanupOutcome> _cleanupAcquisition(
    CaptureAcquisition identity,
  ) async {
    try {
      await identity.started;
    } catch (_) {
      // A failed entered driver start may still own a candidate.
    }
    if (identity._outcome != null) return identity._outcome!;
    if (!identical(identity, _acquisition)) {
      return CaptureCleanupOutcome.mismatch;
    }
    if (_disposed || _driverDisposed) {
      return CaptureCleanupOutcome.disposalUncertain;
    }
    final file = await _stop(recovering: true);
    if (file != null) _cleanupFiles.add(file.path);
    try {
      await _cleanupOwnedFiles();
    } catch (_) {
      throw CaptureLifecycleException();
    }
    if (!identity._driverEntered) {
      identity._outcome = CaptureCleanupOutcome.noDriverEntry;
    } else if (identity._stopConfirmed &&
        !_candidate &&
        !_uncertain &&
        _pendingFile == null &&
        _cleanupFiles.isEmpty) {
      identity._outcome = CaptureCleanupOutcome.cleaned;
    } else {
      throw CaptureLifecycleException();
    }
    return identity._outcome!;
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
    final release = _sessionRelease;
    if (release != null) await release;
    final cleanup = _sessionCleanup;
    if (cleanup != null) {
      try {
        await cleanup;
      } catch (_) {
        // Closing retains its existing explicit cleanup/disposal attempt.
      }
    }
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
    final identity = _acquisition;
    if (identity != null &&
        (identity._outcome == null ||
            identity._outcome == CaptureCleanupOutcome.disposalUncertain)) {
      if (!failed && identity._stopConfirmed && !cleanupPending) {
        identity._outcome = CaptureCleanupOutcome.cleaned;
      } else {
        // Disposal success alone is not evidence of confirmed stop.
        identity._outcome = CaptureCleanupOutcome.disposalUncertain;
      }
    }
    if (failed) throw CaptureLifecycleException();
  }

  @visibleForTesting
  /// Test seam: the path of the current/last capture.
  String? get debugPath => _path;
}
