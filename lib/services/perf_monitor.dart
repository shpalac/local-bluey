import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown by [PerfMonitor.clear] when the stored file could not be removed.
/// The message is generic; details stay in [PerfMonitor.lastStorageError].
class PerfStorageException implements Exception {
  /// Creates the exception with a generic [message].
  const PerfStorageException(this.message);

  /// Safe, user-presentable description.
  final String message;

  @override
  String toString() => message;
}

/// Measures the pipeline's working points (#37): idle, listening
/// (transcription), thinking (brain roundtrip) and acting (tool execution).
/// Samples persist to perf.jsonl for baseline tracking over time.
class PerfMonitor {
  PerfMonitor._({
    Future<File> Function()? file,
    DateTime Function()? clock,
    Future<void> Function(File file, String line)? appendLine,
    Future<void> Function(File file)? deleteFile,
  }) : _fileProvider = file,
       _now = clock ?? DateTime.now,
       _appendLine =
           appendLine ??
           ((f, line) => f.writeAsString(line, mode: FileMode.append)),
       _deleteFile = deleteFile ?? ((f) => f.delete());

  /// A monitor with injected storage and clock, for tests.
  @visibleForTesting
  PerfMonitor.forTest({
    required Future<File> Function() file,
    DateTime Function()? clock,
    Future<void> Function(File file, String line)? appendLine,
    Future<void> Function(File file)? deleteFile,
  }) : this._(
         file: file,
         clock: clock,
         appendLine: appendLine,
         deleteFile: deleteFile,
       );

  /// The app-wide instance.
  static final PerfMonitor instance = PerfMonitor._();

  final Future<File> Function()? _fileProvider;
  final DateTime Function() _now;
  final Future<void> Function(File file, String line) _appendLine;
  final Future<void> Function(File file) _deleteFile;
  final Map<String, List<int>> _samplesMs = {};

  /// Bumped by every [clear]. A measurement that started in an older
  /// generation neither records a sample nor writes to disk, so pre-clear
  /// work can never restore deleted data. Measurements that start after
  /// [clear] begins belong to the new generation and are accepted.
  int _generation = 0;

  /// All file writes and deletions run one at a time, in order.
  Future<void> _io = Future<void>.value();

  /// Last storage failure from an append or a delete, or null. Cleared by the
  /// next successful write or delete.
  final ValueNotifier<String?> lastStorageError = ValueNotifier(null);

  /// Completes when every write and deletion queued so far has settled.
  Future<void> flush() async {
    Future<void> seen;
    do {
      seen = _io;
      await seen;
    } while (!identical(seen, _io));
  }

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _io.then((_) => op());
    // Errors are handled inside each op; this keeps the chain alive anyway.
    _io = next.catchError((_) {});
    return next;
  }

  static const _kOverlay = 'perf_overlay_enabled';

  /// Live flag the face screen listens to for the perf overlay (#61).
  final ValueNotifier<bool> overlayEnabled = ValueNotifier(false);

  /// Whether the perf overlay is enabled; refreshes the live flag.
  Future<bool> isOverlayEnabled() async {
    final v =
        (await SharedPreferences.getInstance()).getBool(_kOverlay) ?? false;
    overlayEnabled.value = v;
    return v;
  }

  /// Persists the overlay setting and updates the live flag.
  Future<void> setOverlayEnabled(bool value) async {
    overlayEnabled.value = value;
    await (await SharedPreferences.getInstance()).setBool(_kOverlay, value);
  }

  /// Deletes samples and resets the overlay preference (#83). Work started
  /// before this call cannot persist afterward; the returned future completes
  /// once the file deletion (queued behind earlier writes) has settled.
  Future<void> clear() async {
    _generation++;
    _samplesMs.clear();
    overlayEnabled.value = false;
    // The queue itself stays alive on failure; the caller still sees it.
    final deletion = _enqueue(() async {
      try {
        final file = await _file();
        if (await file.exists()) await _deleteFile(file);
        lastStorageError.value = null;
      } catch (e) {
        lastStorageError.value = 'PerfMonitor clear failed: $e';
        debugPrint('PerfMonitor clear failed: $e');
        throw const PerfStorageException('Performance data was not deleted');
      }
    });
    await (await SharedPreferences.getInstance()).remove(_kOverlay);
    await deletion;
  }

  Future<T> measure<T>(String stage, Future<T> Function() work) async {
    final generation = _generation;
    final start = _now();
    try {
      return await work();
    } finally {
      if (generation == _generation) {
        final ms = _now().difference(start).inMilliseconds;
        _samplesMs.putIfAbsent(stage, () => []).add(ms);
        unawaited(_append(stage, ms, generation));
      }
    }
  }

  /// Median per stage, the baseline the docs track.
  Map<String, int> medians() => {
    for (final entry in _samplesMs.entries) entry.key: _median(entry.value),
  };

  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  Future<File> _file() async => _fileProvider != null
      ? _fileProvider()
      : File('${(await getApplicationDocumentsDirectory()).path}/perf.jsonl');

  Future<void> _append(
    String stage,
    int ms,
    int generation,
  ) => _enqueue(() async {
    // Re-checked when the write actually runs: a clear that arrived while
    // this append was queued wins.
    if (generation != _generation) return;
    try {
      await _appendLine(
        await _file(),
        '${jsonEncode({'stage': stage, 'ms': ms, 'at': _now().toIso8601String()})}\n',
      );
      lastStorageError.value = null;
    } catch (e) {
      lastStorageError.value = 'PerfMonitor write failed: $e';
      debugPrint('PerfMonitor write failed: $e');
    }
  });
}
