import 'dart:convert';
import 'dart:io';

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

  factory EgressEntry.fromJson(Map<String, dynamic> json) {
    final host = json['host'];
    final kind = json['kind'];
    final bytes = json['bytes'];
    final at = DateTime.tryParse('${json['at']}');
    if (host is! String ||
        host.isEmpty ||
        host.contains('/') ||
        host.contains('@') ||
        kind is! String ||
        kind.isEmpty ||
        bytes is! int ||
        bytes < 0 ||
        at == null) {
      throw const FormatException('Invalid egress metadata');
    }
    return EgressEntry(host: host, kind: kind, bytes: bytes, at: at);
  }
}

/// Storage holds metadata only. Null from read means no retained file.
abstract interface class EgressStorage {
  /// Reads retained lines, or null when the file is absent.
  Future<String?> read();

  /// Replaces the retained metadata; failures must throw.
  Future<void> write(String contents);

  /// Deletes retained history; failures must throw.
  Future<void> delete();
}

class _FileEgressStorage implements EgressStorage {
  Future<File> _file() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/egress.jsonl');

  @override
  Future<String?> read() async {
    final file = await _file();
    return await file.exists() ? await file.readAsString() : null;
  }

  @override
  Future<void> write(String contents) async {
    await (await _file()).writeAsString(contents, flush: true);
  }

  @override
  Future<void> delete() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

/// Bounded retained metadata, not proof that all historical egress is known.
class EgressMonitor {
  EgressMonitor({EgressStorage? storage, DateTime Function()? now})
    : _storage = storage ?? _FileEgressStorage(),
      _now = now ?? DateTime.now;

  /// Shared production monitor.
  static final EgressMonitor instance = EgressMonitor();

  /// Maximum retained metadata entries.
  static const keepEntries = 300;

  /// Maximum retained age in days.
  static int retentionDays = 30;

  final EgressStorage _storage;
  final DateTime Function() _now;

  /// In-memory retained entries, oldest first.
  final List<EgressEntry> entries = [];
  Future<void> _tail = Future<void>.value();
  bool _loaded = false;
  bool _readFailed = false;
  bool _incomplete = false;
  String? _storageProblem;

  /// Whether the retained history was recovered without known gaps/errors.
  bool get historyAvailable =>
      _loaded && !_readFailed && !_incomplete && _storageProblem == null;

  /// All disk reads/writes/deletion share one queue. A completed clear is
  /// necessarily after every older operation, so none can resurrect history.
  Future<void> _ordered(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  /// Idempotently recovers retained history in operation order.
  Future<void> load() => _ordered(_load);

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final contents = await _storage.read();
      final recovered = <EgressEntry>[];
      for (final line in const LineSplitter().convert(contents ?? '')) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line);
          if (json is! Map<String, dynamic>) {
            throw const FormatException('Invalid egress row');
          }
          recovered.add(EgressEntry.fromJson(json));
        } catch (_) {
          _incomplete = true;
        }
      }
      entries.insertAll(0, recovered);
      _loaded = true;
      _readFailed = false;
      _storageProblem = null;
      _prune();
    } catch (_) {
      // Do not overwrite unknown disk history with a new partial log.
      _readFailed = true;
      _storageProblem = 'Retained egress history is unavailable.';
    }
  }

  void _prune() {
    final cutoff = _now().subtract(Duration(days: retentionDays));
    entries.removeWhere((e) => e.at.isBefore(cutoff));
    entries.sort((a, b) => a.at.compareTo(b.at));
    if (entries.length > keepEntries) {
      entries.removeRange(0, entries.length - keepEntries);
    }
  }

  /// Records metadata only after loading history, then persists in order.
  Future<void> record(String url, String kind, int bytes) {
    // Never use an unparsed URL as a host: it may contain a path or secret.
    final host = Uri.tryParse(url)?.host;
    final entry = EgressEntry(
      host: host == null || host.isEmpty ? 'unknown-host' : host,
      kind: kind,
      bytes: bytes < 0 ? 0 : bytes,
      at: _now(),
    );
    return _ordered(() async {
      await _load();
      entries.add(entry);
      _prune();
      if (_readFailed || _incomplete) return;
      try {
        final lines = entries.map((e) => jsonEncode(e.toJson())).join('\n');
        await _storage.write(lines.isEmpty ? '' : '$lines\n');
        _storageProblem = null;
      } catch (_) {
        _storageProblem = 'Egress history could not be saved.';
      }
    });
  }

  static bool _isLocalHost(String host) =>
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host.endsWith('.local');

  /// Delete after all older operations. A failed delete is surfaced and does
  /// not claim cleared disk history; a successful clear establishes a new log.
  Future<void> clear() => _ordered(() async {
    entries.clear();
    try {
      await _storage.delete();
      _loaded = true;
      _readFailed = false;
      _incomplete = false;
      _storageProblem = null;
    } catch (_) {
      _loaded = false;
      _readFailed = true;
      _storageProblem = 'Egress history deletion failed.';
      rethrow;
    }
  });

  /// "what was sent, where, when" - one line per destination.
  String report() {
    _prune();
    final warning = !historyAvailable
        ? '${_storageProblem ?? 'Retained egress history is not fully available.'}\n'
        : '';
    if (entries.isEmpty) {
      return '${warning}No transmissions in the retained record.';
    }
    final byHost = <String, List<EgressEntry>>{};
    for (final e in entries) {
      byHost.putIfAbsent(e.host, () => []).add(e);
    }
    return warning +
        byHost.entries
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
    await load();
    _prune();
    final problems = <String>[];
    if (!historyAvailable) {
      problems.add('Retained egress history is unavailable or incomplete.');
    }
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
