import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ConversationEntry {
  ConversationEntry({required this.role, required this.text, DateTime? at})
    : at = at ?? DateTime.now();

  final String role; // 'user' or 'bluey'
  final String text;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    'at': at.toIso8601String(),
  };

  factory ConversationEntry.fromJson(Map<String, dynamic> json) =>
      ConversationEntry(
        role: json['role'] as String? ?? 'bluey',
        text: json['text'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// The persistent, scrollable answer log. Survives restarts via a JSON file
/// in the app documents directory.
class ConversationStore extends ChangeNotifier {
  ConversationStore._();
  static final ConversationStore instance = ConversationStore._();

  static const maxEntries = 200;

  final List<ConversationEntry> entries = [];
  bool _loaded = false;

  Future<File> _file() async => File(
    '${(await getApplicationDocumentsDirectory()).path}/conversation.json',
  );

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await (await _file()).readAsString();
      final list = List<dynamic>.from(jsonDecode(raw) as List);
      entries.addAll(
        list.map(
          (e) => ConversationEntry.fromJson(Map<String, dynamic>.from(e)),
        ),
      );
      notifyListeners();
    } catch (_) {
      // No history yet.
    }
  }

  Future<void> add(String role, String text) async {
    if (text.trim().isEmpty) return;
    entries.add(ConversationEntry(role: role, text: text));
    while (entries.length > maxEntries) {
      entries.removeAt(0);
    }
    notifyListeners();
    try {
      await (await _file()).writeAsString(
        jsonEncode(entries.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Persistence is best-effort; the in-memory log still works.
    }
  }

  Future<void> clear() async {
    entries.clear();
    notifyListeners();
    try {
      await (await _file()).delete();
    } catch (_) {}
  }
}
