import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One stored turn in the on-device conversation log.
class ConversationEntry {
  ConversationEntry({required this.role, required this.text, DateTime? at})
    : at = at ?? DateTime.now();

  /// 'user' or 'bluey'.
  final String role;

  /// The turn's text.
  final String text;

  /// When the turn happened (defaults to now).
  final DateTime at;

  /// Serializes for the on-disk log.
  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    'at': at.toIso8601String(),
  };

  factory ConversationEntry.fromJson(Map<String, dynamic> json) {
    final role = json['role'];
    final text = json['text'];
    final at = json['at'] is String ? DateTime.tryParse(json['at']) : null;
    if ((role != 'user' && role != 'bluey') || text is! String || at == null) {
      throw const FormatException('Invalid conversation row');
    }
    return ConversationEntry(role: role as String, text: text, at: at);
  }
}

/// Persisted conversation JSON. Null reads mean an absent file, not failure.
abstract interface class ConversationStorage {
  /// Reads retained history, or null if absent. Failures throw.
  Future<String?> read();

  /// Replaces retained history. Failures throw.
  Future<void> write(String contents);

  /// Deletes retained history. Failures throw.
  Future<void> delete();
}

/// Local file storage with an injectable file resolver.
class FileConversationStorage implements ConversationStorage {
  /// Resolves [file] for each operation.
  FileConversationStorage(this.file);

  /// File resolver for production or temp-directory fixtures.
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

/// Bounded local answer log. Recovery/add/deletion share one ordered queue.
/// This orders calls to the store, not later adds from work outside the store.
class ConversationStore extends ChangeNotifier {
  /// Uses injected storage/clock for independent offline fixtures.
  ConversationStore({ConversationStorage? storage, DateTime Function()? now})
    : _storage =
          storage ??
          FileConversationStorage(
            () async => File(
              '${(await getApplicationDocumentsDirectory()).path}/conversation.json',
            ),
          ),
      _now = now ?? DateTime.now;

  /// The shared production store.
  static final ConversationStore instance = ConversationStore();

  /// Maximum retained entries; oldest entries drop off.
  static const maxEntries = 200;
  final ConversationStorage _storage;
  final DateTime Function() _now;
  final List<ConversationEntry> _entries = [];

  /// Immutable entries view, oldest first.
  List<ConversationEntry> get entries => List.unmodifiable(_entries);
  Future<void> _tail = Future<void>.value();
  bool _loaded = false, _readFailed = false, _incomplete = false;
  String? _problem;

  /// True only after known-complete recovery and successful storage.
  bool get historyAvailable =>
      _loaded && !_readFailed && !_incomplete && _problem == null;

  /// History uncertainty, or null when available.
  String? get historyProblem => historyAvailable
      ? null
      : _problem ??
            'Retained conversation history is unavailable or incomplete.';

  Future<void> _ordered(Future<void> Function() op) {
    final next = _tail.then((_) => op());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _cap() {
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  /// Idempotently recovers retained entries in store-call order.
  Future<void> load() => _ordered(_load);
  Future<void> _load() async {
    if (_loaded) return;
    try {
      final raw = await _storage.read();
      final recovered = <ConversationEntry>[];
      if (raw != null) {
        final json = jsonDecode(raw);
        if (json is! List) {
          throw const FormatException('Invalid conversation file');
        }
        for (final row in json) {
          try {
            if (row is! Map<String, dynamic>) {
              throw const FormatException('Invalid row');
            }
            recovered.add(ConversationEntry.fromJson(row));
          } catch (_) {
            _incomplete = true;
          }
        }
      }
      _entries.insertAll(0, recovered);
      _cap();
      _loaded = true;
      _readFailed = false;
      _problem = null;
    } on FormatException {
      _loaded = true;
      _incomplete = true;
      _problem = 'Retained conversation history is malformed.';
    } catch (_) {
      _readFailed = true;
      _problem = 'Retained conversation history could not be read.';
    }
    notifyListeners();
  }

  /// Recovers before appending a nonblank turn, then persists in order.
  /// Unknown/corrupt retained bytes are preserved until explicit deletion.
  Future<void> add(String role, String text) {
    if (text.trim().isEmpty) return Future<void>.value();
    final entry = ConversationEntry(role: role, text: text, at: _now());
    return _ordered(() async {
      await _load();
      _entries.add(entry);
      _cap();
      if (!_readFailed && !_incomplete) {
        try {
          await _storage.write(
            jsonEncode(_entries.map((e) => e.toJson()).toList()),
          );
          _problem = null;
        } catch (_) {
          _problem = 'Conversation history could not be saved.';
        }
      }
      notifyListeners();
    });
  }

  /// Deletes after older calls. Failed deletion propagates and keeps memory.
  Future<void> clear() => _ordered(() async {
    try {
      await _storage.delete();
      _entries.clear();
      _loaded = true;
      _readFailed = false;
      _incomplete = false;
      _problem = null;
    } catch (_) {
      _readFailed = true;
      _problem = 'Conversation history deletion failed.';
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  });
}
