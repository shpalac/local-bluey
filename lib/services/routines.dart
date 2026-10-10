import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A user-defined macro: a spoken trigger expands into standing instructions
/// for the brain ("work mode" -> silence notifications, open the editor,
/// read the task board). Skills share as JSON (#56).
class Routine {
  const Routine({
    required this.name,
    required this.trigger,
    required this.instructions,
    this.enabled = true,
  });

  /// Display name, also the storage key.
  final String name;

  /// Lowercase phrase matched against the user's utterance.
  final String trigger;

  /// What the brain should do when the trigger fires.
  final String instructions;

  /// Disabled routines are kept but never matched.
  final bool enabled;

  /// Serializes for on-disk storage.
  Map<String, dynamic> toJson() => {
    'name': name,
    'trigger': trigger,
    'instructions': instructions,
    'enabled': enabled,
  };

  factory Routine.fromJson(Map<String, dynamic> json) => Routine(
    name: json['name'] as String? ?? '',
    trigger: (json['trigger'] as String? ?? '').toLowerCase(),
    instructions: json['instructions'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
  );
}

/// Loads and persists user routines (trigger phrase -> instructions).
class RoutineStore {
  RoutineStore._({
    Future<File> Function()? file,
    Future<void> Function(File staging, String contents)? stage,
    Future<void> Function(File staging, String path)? commit,
  }) : _fileProvider = file,
       _stage =
           stage ?? ((f, contents) => f.writeAsString(contents, flush: true)),
       _commit = commit ?? ((f, path) => f.rename(path));

  /// A store over injected storage, for tests.
  @visibleForTesting
  RoutineStore.forTest({
    required Future<File> Function() file,
    Future<void> Function(File staging, String contents)? stage,
    Future<void> Function(File staging, String path)? commit,
  }) : this._(file: file, stage: stage, commit: commit);

  final Future<File> Function()? _fileProvider;
  final Future<void> Function(File staging, String contents) _stage;
  final Future<void> Function(File staging, String path) _commit;

  /// The shared store.
  static final RoutineStore instance = RoutineStore._();

  /// The in-memory routines.
  final List<Routine> routines = [];
  bool _loaded = false;

  Future<File> _file() async => _fileProvider != null
      ? _fileProvider()
      : File(
          '${(await getApplicationDocumentsDirectory()).path}/routines.json',
        );

  /// Loads routines from disk.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await (await _file()).readAsString();
      final list = List<dynamic>.from(jsonDecode(raw) as List);
      routines.addAll(
        list.map((e) => Routine.fromJson(Map<String, dynamic>.from(e as Map))),
      );
    } catch (e) {
      debugPrint('RoutineStore load failed: $e');
    }
  }

  /// Persists the current list.
  Future<void> save() async {
    try {
      await (await _file()).writeAsString(
        jsonEncode(routines.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('RoutineStore save failed: $e');
    }
  }

  /// Deletes all routines, in memory and on disk (#83).
  Future<void> clear() async {
    routines.clear();
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('RoutineStore clear failed: $e');
    }
  }

  /// Adds (or replaces by name) and persists.
  Future<void> add(Routine routine) async {
    routines.removeWhere((r) => r.name == routine.name);
    routines.add(routine);
    await save();
  }

  /// Removes by name and persists.
  Future<void> remove(String name) async {
    routines.removeWhere((r) => r.name == name);
    await save();
  }

  /// The routine this utterance triggers, if any.
  Routine? match(String utterance) {
    final text = utterance.toLowerCase();
    for (final r in routines) {
      if (r.enabled && r.trigger.isNotEmpty && text.contains(r.trigger)) {
        return r;
      }
    }
    return null;
  }

  /// Shareable skill pack: routines as portable JSON.
  String export() => jsonEncode(routines.map((r) => r.toJson()).toList());

  /// Largest accepted pack, in characters.
  static const maxPackChars = 256 * 1024;

  /// Most routines one pack may carry.
  static const maxPackRoutines = 100;

  /// Longest accepted routine name.
  static const maxNameChars = 80;

  /// Longest accepted trigger phrase.
  static const maxTriggerChars = 120;

  /// Longest accepted instruction text.
  static const maxInstructionsChars = 4000;

  /// Imports a portable pack and returns how many routines were added.
  ///
  /// The whole pack is validated first. Accepted shapes: a top-level list
  /// (the original export format) or `{"version": 1, "routines": [...]}`.
  /// Any invalid entry, a duplicate name inside the pack, or a name that
  /// already exists rejects the pack with [RoutineImportException] and
  /// changes nothing, in memory or on disk. A valid pack is written once and
  /// published in memory only after that write succeeds. Import only stores
  /// data; it never runs a routine.
  Future<int> importFrom(String json) async {
    final incoming = _parsePack(json);
    final taken = {for (final r in routines) r.name};
    final seen = <String>{};
    for (final r in incoming) {
      if (!seen.add(r.name)) {
        throw const RoutineImportException('Pack repeats a routine name');
      }
      if (taken.contains(r.name)) {
        throw const RoutineImportException(
          'A routine with that name already exists',
        );
      }
    }
    if (incoming.isEmpty) return 0;
    final next = [...routines, ...incoming];
    try {
      await _write(next);
    } catch (e) {
      debugPrint('RoutineStore import write failed: $e');
      throw const RoutineImportException('Routines could not be saved');
    }
    routines.addAll(incoming);
    return incoming.length;
  }

  /// Writes [list] to a same-directory staging file, then atomically
  /// replaces routines.json. A failure at either step leaves the original
  /// file untouched and removes the staging file.
  Future<void> _write(List<Routine> list) async {
    final target = await _file();
    final staging = File('${target.path}.tmp');
    try {
      await _stage(staging, jsonEncode(list.map((r) => r.toJson()).toList()));
      await _commit(staging, target.path);
    } catch (_) {
      try {
        if (staging.existsSync()) staging.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  static List<Routine> _parsePack(String json) {
    if (json.length > maxPackChars) {
      throw const RoutineImportException('Pack is too large');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const RoutineImportException('Pack is not valid JSON');
    }
    Object? entries = decoded;
    if (decoded is Map) {
      if (decoded['version'] != 1) {
        throw const RoutineImportException('Unsupported pack version');
      }
      entries = decoded['routines'];
    }
    if (entries is! List) {
      throw const RoutineImportException('Pack must contain a routine list');
    }
    if (entries.length > maxPackRoutines) {
      throw const RoutineImportException('Pack has too many routines');
    }
    return [for (final e in entries) _parseEntry(e)];
  }

  static Routine _parseEntry(Object? e) {
    if (e is! Map) {
      throw const RoutineImportException('A routine entry is not an object');
    }
    String text(String key, int max) {
      final v = e[key];
      if (v is! String || v.trim().isEmpty) {
        throw RoutineImportException('Routine field "$key" is missing');
      }
      if (v.length > max) {
        throw RoutineImportException('Routine field "$key" is too long');
      }
      return v;
    }

    final enabled = e['enabled'];
    if (enabled != null && enabled is! bool) {
      throw const RoutineImportException(
        'Routine "enabled" must be true/false',
      );
    }
    return Routine(
      name: text('name', maxNameChars),
      trigger: text('trigger', maxTriggerChars).toLowerCase(),
      instructions: text('instructions', maxInstructionsChars),
      enabled: enabled as bool? ?? true,
    );
  }
}

/// Thrown when a routine pack is rejected; nothing was changed. Messages are
/// generic and never echo pack content.
class RoutineImportException implements Exception {
  /// Creates the exception with a generic [message].
  const RoutineImportException(this.message);

  /// Safe description of why the pack was rejected.
  final String message;

  @override
  String toString() => message;
}
