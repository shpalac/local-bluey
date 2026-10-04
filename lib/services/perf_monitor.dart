import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Measures the pipeline's working points (#37): idle, listening
/// (transcription), thinking (brain roundtrip) and acting (tool execution).
/// Samples persist to perf.jsonl for baseline tracking over time.
class PerfMonitor {
  PerfMonitor._();
  static final PerfMonitor instance = PerfMonitor._();

  final Map<String, List<int>> _samplesMs = {};

  Future<T> measure<T>(String stage, Future<T> Function() work) async {
    final start = DateTime.now();
    try {
      return await work();
    } finally {
      final ms = DateTime.now().difference(start).inMilliseconds;
      _samplesMs.putIfAbsent(stage, () => []).add(ms);
      unawaited(_append(stage, ms));
    }
  }

  /// Median per stage, the baseline the docs track.
  Map<String, int> medians() => {
    for (final entry in _samplesMs.entries)
      entry.key: _median(entry.value),
  };

  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  Future<File> _file() async => File(
    '${(await getApplicationDocumentsDirectory()).path}/perf.jsonl',
  );

  Future<void> _append(String stage, int ms) async {
    try {
      await (await _file()).writeAsString(
        '${jsonEncode({'stage': stage, 'ms': ms, 'at': DateTime.now().toIso8601String()})}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }
}
