import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

// Bounds are storage limits, not a guarantee of secret detection. Arbitrary
// argument/outcome text may still be private. No payload leaves this device.
String _text(String value, int bytes) {
  final out = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final size = utf8.encode(char).length;
    if (used + size > bytes) break;
    out.write(char);
    used += size;
  }
  return out.toString();
}

class _ArgumentSnapshot {
  var remaining = 8192;
  var nodes = 128;

  String text(String value, int limit) {
    final result = _text(value, remaining < limit ? remaining : limit);
    remaining -= utf8.encode(result).length;
    return result;
  }

  dynamic copy(dynamic value, int depth) {
    if (remaining <= 0 || nodes-- <= 0 || depth > 4) return null;
    if (value == null || value is bool || value is int) return value;
    if (value is double) return value.isFinite ? value : null;
    if (value is String) return text(value, 1024);
    if (value is Map) {
      final map = <String, dynamic>{};
      for (final entry in value.entries.take(32)) {
        if (remaining <= 0 || nodes <= 0) break;
        if (entry.key is! String) continue;
        final key = text(entry.key as String, 128);
        map[key] = copy(entry.value, depth + 1);
      }
      return Map<String, dynamic>.unmodifiable(map);
    }
    if (value is List) {
      final list = <dynamic>[];
      for (final item in value.take(32)) {
        if (remaining <= 0 || nodes <= 0) break;
        list.add(copy(item, depth + 1));
      }
      return List<dynamic>.unmodifiable(list);
    }
    // Do not call arbitrary object.toString() or retain caller-owned objects.
    return null;
  }
}

/// Immutable bounded snapshot of one executed action (#57).
class ActionEntry {
  ActionEntry({
    required String runId,
    required String tool,
    required Map<String, dynamic> arguments,
    required String outcome,
    DateTime? at,
    String? recoveryHint,
  }) : runId = _text(runId, 256),
       tool = _text(tool, 128),
       arguments =
           _ArgumentSnapshot().copy(arguments, 0) as Map<String, dynamic>,
       outcome = _text(outcome, 2048),
       recoveryHint = recoveryHint == null ? null : _text(recoveryHint, 1024),
       at = at ?? DateTime.now();

  /// Actions from one brain turn share this bounded id.
  final String runId;

  /// Tool name.
  final String tool;

  /// Bounded, detached arguments, not necessarily the full executed payload.
  final Map<String, dynamic> arguments;

  /// Bounded tool result or error.
  final String outcome;

  /// Bounded recovery guidance.
  final String? recoveryHint;

  /// Time of execution.
  final DateTime at;

  /// Failure is recorded even if its guidance was truncated.
  bool get failed => recoveryHint != null;

  /// Serializes bounded retained fields.
  Map<String, dynamic> toJson() => {
    'runId': runId,
    'tool': tool,
    'arguments': arguments,
    'outcome': outcome,
    if (recoveryHint != null) 'recoveryHint': recoveryHint,
    'at': at.toIso8601String(),
  };

  factory ActionEntry.fromJson(Map<String, dynamic> json) {
    final at = json['at'] is String ? DateTime.tryParse(json['at']) : null;
    if (json['runId'] is! String ||
        json['tool'] is! String ||
        json['arguments'] is! Map<String, dynamic> ||
        json['outcome'] is! String ||
        (json['recoveryHint'] != null && json['recoveryHint'] is! String) ||
        at == null) {
      throw const FormatException('Invalid action row');
    }
    return ActionEntry(
      runId: json['runId'],
      tool: json['tool'],
      arguments: json['arguments'],
      outcome: json['outcome'],
      recoveryHint: json['recoveryHint'],
      at: at,
    );
  }
}

/// Null read means absent storage, not a failed read. Failures must throw.
abstract interface class ActionStorage {
  /// Reads retained JSONL; null means absent file.
  Future<String?> read();

  /// Replaces retained history; throws on failure.
  Future<void> write(String contents);

  /// Deletes retained history; throws on failure.
  Future<void> delete();
}

/// Local JSONL storage with an injectable file resolver.
class FileActionStorage implements ActionStorage {
  /// Uses [file] for each operation.
  FileActionStorage(this.file);

  /// Resolves the target file.
  final Future<File> Function() file;
  @override
  Future<String?> read() async {
    final f = await file();
    return await f.exists() ? await f.readAsString() : null;
  }

  @override
  Future<void> write(String contents) async {
    await (await file()).writeAsString(contents, flush: true);
  }

  @override
  Future<void> delete() async {
    final f = await file();
    if (await f.exists()) await f.delete();
  }
}

/// Bounded retained action history. Corrupt/unknown history is not overwritten.
class ActionLog {
  ActionLog({ActionStorage? storage, DateTime Function()? now})
    : _storage =
          storage ??
          FileActionStorage(
            () async => File(
              '${(await getApplicationDocumentsDirectory()).path}/actions.jsonl',
            ),
          ),
      _now = now ?? DateTime.now;

  /// Shared production log.
  static final ActionLog instance = ActionLog();

  /// Maximum retained entry count.
  static const keepEntries = 500;

  /// Maximum retained age in days.
  static int retentionDays = 30;
  final ActionStorage _storage;
  final DateTime Function() _now;
  final List<ActionEntry> _entries = [];

  /// Immutable view of retained entries in record order.
  List<ActionEntry> get entries => List.unmodifiable(_entries);
  Future<void> _tail = Future<void>.value();
  bool _loaded = false, _incomplete = false, _readFailed = false;
  String? _problem;

  /// True only after known-complete recovery and successful storage.
  bool get historyAvailable =>
      _loaded && !_incomplete && !_readFailed && _problem == null;

  /// Current history uncertainty, or null when available.
  String? get historyProblem => historyAvailable
      ? null
      : _problem ?? 'Retained action history is unavailable or incomplete.';

  Future<void> _ordered(Future<void> Function() op) {
    final next = _tail.then((_) => op());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  /// Idempotently recovers history in operation order.
  Future<void> load() => _ordered(_load);
  Future<void> _load() async {
    if (_loaded) return;
    try {
      final contents = await _storage.read();
      final recovered = <ActionEntry>[];
      for (final line in const LineSplitter().convert(contents ?? '')) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line);
          if (json is! Map<String, dynamic>) throw const FormatException('row');
          recovered.add(ActionEntry.fromJson(json));
        } catch (_) {
          _incomplete = true;
        }
      }
      _entries.insertAll(0, recovered);
      _loaded = true;
      _readFailed = false;
      _problem = null;
      _prune();
    } catch (_) {
      _readFailed = true;
      _problem = 'Retained action history could not be read.';
    }
  }

  void _prune() {
    final cutoff = _now().subtract(Duration(days: retentionDays));
    _entries.removeWhere((e) => e.at.isBefore(cutoff));
    if (_entries.length > keepEntries) {
      _entries.removeRange(0, _entries.length - keepEntries);
    }
  }

  /// Loads first, then appends and persists in order.
  Future<void> record(ActionEntry entry) => _ordered(() async {
    await _load();
    _entries.add(entry);
    _prune();
    if (_readFailed || _incomplete) return;
    try {
      final lines = _entries.map((e) => jsonEncode(e.toJson())).join('\n');
      await _storage.write(lines.isEmpty ? '' : '$lines\n');
      _problem = null;
    } catch (_) {
      _problem = 'Action history could not be saved.';
    }
  });

  /// Deletes after all older operations. Failure propagates to DataRegistry.
  Future<void> clear() => _ordered(() async {
    try {
      await _storage.delete();
      _entries.clear();
      _loaded = true;
      _readFailed = false;
      _incomplete = false;
      _problem = null;
    } catch (_) {
      _problem = 'Action history deletion failed.';
      _readFailed = true;
      rethrow;
    }
  });

  /// Per-run outcome/recovery summary, with any known history warning.
  String summarizeRun(String runId) {
    _prune();
    final warning = historyProblem == null ? '' : '${historyProblem!}\n';
    final run = _entries.where((e) => e.runId == runId).toList();
    if (run.isEmpty) return '${warning}No actions in this run.';
    final failed = run.where((e) => e.failed).toList();
    final buffer = StringBuffer('$warning${run.length} actions');
    if (failed.isEmpty) return '$buffer, all succeeded.';
    buffer.write(', ${failed.length} failed: ');
    buffer.write(failed.map((e) => '${e.tool} (${e.recoveryHint})').join('; '));
    return buffer.toString();
  }
}
