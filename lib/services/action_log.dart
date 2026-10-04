import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One executed action, persisted so "what did Bluey just do?" is always
/// answerable (#57).
class ActionEntry {
  ActionEntry({
    required this.runId,
    required this.tool,
    required this.arguments,
    required this.outcome,
    DateTime? at,
    this.recoveryHint,
  }) : at = at ?? DateTime.now();

  /// All actions from one brain turn share a run id, so a run can be
  /// summarized or audited as a unit.
  final String runId;
  final String tool;
  final Map<String, dynamic> arguments;

  /// First line of the tool result, or the error message.
  final String outcome;

  /// What to try when this action failed, in plain language.
  final String? recoveryHint;
  final DateTime at;

  bool get failed => recoveryHint != null;

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'tool': tool,
    'arguments': arguments,
    'outcome': outcome,
    if (recoveryHint != null) 'recoveryHint': recoveryHint,
    'at': at.toIso8601String(),
  };

  factory ActionEntry.fromJson(Map<String, dynamic> json) => ActionEntry(
    runId: json['runId'] as String? ?? '',
    tool: json['tool'] as String? ?? '',
    arguments: Map<String, dynamic>.from(json['arguments'] as Map? ?? const {}),
    outcome: json['outcome'] as String? ?? '',
    recoveryHint: json['recoveryHint'] as String?,
    at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
  );
}

/// Persistent, append-only action log (actions.jsonl in app documents).
class ActionLog {
  ActionLog._();
  static final ActionLog instance = ActionLog._();

  static const keepEntries = 500;

  /// Entries older than this are pruned on every write (#83).
  static int retentionDays = 30;

  final List<ActionEntry> entries = [];

  Future<File> _file() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/actions.jsonl');

  Future<void> record(ActionEntry entry) async {
    entries.add(entry);
    entries.removeWhere(
      (e) => DateTime.now().difference(e.at).inDays > retentionDays,
    );
    while (entries.length > keepEntries) {
      entries.removeAt(0);
    }
    try {
      final file = await _file();
      final lines = entries.map((e) => jsonEncode(e.toJson())).join('\n');
      await file.writeAsString('$lines\n', flush: true);
    } catch (e) {
      debugPrint('ActionLog write failed: $e');
    }
  }

  /// Deletes the log, in memory and on disk (#83).
  Future<void> clear() async {
    entries.clear();
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('ActionLog clear failed: $e');
    }
  }

  /// Per-run summary: "3 actions, 1 failed (click: re-look at the screen)".
  String summarizeRun(String runId) {
    final run = entries.where((e) => e.runId == runId).toList();
    if (run.isEmpty) return 'No actions in this run.';
    final failed = run.where((e) => e.failed).toList();
    final buffer = StringBuffer('${run.length} actions');
    if (failed.isEmpty) return '$buffer, all succeeded.';
    buffer.write(', ${failed.length} failed: ');
    buffer.write(failed.map((e) => '${e.tool} (${e.recoveryHint})').join('; '));
    return buffer.toString();
  }
}
