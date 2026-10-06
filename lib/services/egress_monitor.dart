import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'privacy_guard.dart';
import 'settings_store.dart';

/// One outbound transmission: where it went, what kind of data, how much.
class EgressEntry {
  EgressEntry({
    required this.host,
    required this.kind,
    required this.bytes,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  /// The destination host (no path, no payload).
  final String host;

  /// brain | transcription | tts
  final String kind;

  /// Bytes transmitted.
  final int bytes;

  /// When it happened (defaults to now).
  final DateTime at;

  /// Serializes for the on-disk log.
  Map<String, dynamic> toJson() => {
    'host': host,
    'kind': kind,
    'bytes': bytes,
    'at': at.toIso8601String(),
  };

  factory EgressEntry.fromJson(Map<String, dynamic> json) => EgressEntry(
    host: json['host'] as String? ?? '',
    kind: json['kind'] as String? ?? '',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
  );
}

/// Verifiable record of everything that left the Mac (#58): what, where,
/// when. Checkable against network tools; nothing is sent that is not here.
class EgressMonitor {
  EgressMonitor._();

  /// The shared monitor.
  static final EgressMonitor instance = EgressMonitor._();

  /// Rolling cap on retained entries.
  static const keepEntries = 300;

  /// Entries older than this are pruned on every write (#83).
  static int retentionDays = 30;

  /// The in-memory log, oldest first.
  final List<EgressEntry> entries = [];

  /// Logs one transmission: host + kind + bytes, never the payload.
  Future<void> record(String url, String kind, int bytes) async {
    final host = Uri.tryParse(url)?.host ?? url;
    entries.add(EgressEntry(host: host, kind: kind, bytes: bytes));
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
      debugPrint('EgressMonitor write failed: $e');
    }
  }

  static bool _isLocalHost(String host) =>
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host.endsWith('.local');

  Future<File> _file() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/egress.jsonl');

  /// Deletes the record, in memory and on disk (#83).
  Future<void> clear() async {
    entries.clear();
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('EgressMonitor clear failed: $e');
    }
  }

  /// "what was sent, where, when" - one line per destination.
  String report() {
    if (entries.isEmpty) return 'Nothing has left this Mac.';
    final byHost = <String, List<EgressEntry>>{};
    for (final e in entries) {
      byHost.putIfAbsent(e.host, () => []).add(e);
    }
    return byHost.entries
        .map((entry) {
          final total = entry.value.fold<int>(0, (s, e) => s + e.bytes);
          final kinds = entry.value.map((e) => e.kind).toSet().join(', ');
          final last = entry.value.last.at;
          return '${entry.key}: ${entry.value.length} calls ($kinds), '
              '$total bytes, last $last';
        })
        .join('\n');
  }

  /// Offline self-test: every configured endpoint must resolve to this
  /// machine, and the log must show no remote host.
  Future<List<String>> offlineSelfTest(BrainSettings settings) async {
    final problems = <String>[];
    final endpoints = {
      'brain': settings.baseUrl,
      'transcription': settings.transcriptionBaseUrl ?? settings.baseUrl,
      'tts': settings.ttsBaseUrl ?? settings.baseUrl,
    };
    endpoints.forEach((kind, url) {
      if (!PrivacyGuard.isLocalUrl(url)) {
        problems.add('$kind endpoint is remote: $url');
      }
    });
    final remote = entries.where((e) => !_isLocalHost(e.host));
    if (remote.isNotEmpty) {
      final hosts = remote.map((e) => e.host).toSet().join(', ');
      problems.add('log shows past transmissions to: $hosts');
    }
    return problems;
  }
}
