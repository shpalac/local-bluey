import 'dart:async';
import 'dart:collection';
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
    Future<String> Function(File file)? read,
    Future<void> Function(File file)? delete,
  }) : _fileProvider = file,
       _read = read ?? ((f) => f.readAsString()),
       _delete = delete ?? ((f) => f.delete()),
       _stage =
           stage ?? ((f, contents) => f.writeAsString(contents, flush: true)),
       _commit = commit ?? ((f, path) => f.rename(path));

  /// A store over injected storage, for tests.
  @visibleForTesting
  RoutineStore.forTest({
    required Future<File> Function() file,
    Future<void> Function(File staging, String contents)? stage,
    Future<void> Function(File staging, String path)? commit,
    Future<String> Function(File file)? read,
    Future<void> Function(File file)? delete,
  }) : this._(
         file: file,
         stage: stage,
         commit: commit,
         read: read,
         delete: delete,
       );

  final Future<File> Function()? _fileProvider;
  final Future<void> Function(File staging, String contents) _stage;
  final Future<void> Function(File staging, String path) _commit;
  final Future<String> Function(File file) _read;
  final Future<void> Function(File file) _delete;

  /// The shared store.
  static final RoutineStore instance = RoutineStore._();

  final List<Routine> _routines = [];

  /// The loaded routines, read-only. Change them through [add], [remove],
  /// [importFrom] and [clear] so every change is persisted.
  List<Routine> get routines => UnmodifiableListView(_routines);

  /// Replaces the in-memory list without touching storage (tests only).
  @visibleForTesting
  void seed(List<Routine> list) {
    _routines
      ..clear()
      ..addAll(list);
    _loaded = true;
  }

  bool _loaded = false;
  bool _incomplete = false;

  /// Why saved routines could not be fully read, or null. While this is set
  /// the store refuses changes so the unreadable file is never overwritten;
  /// a later [load] retries a transient read failure and [clear] is the
  /// explicit way to discard an unreadable file.
  final ValueNotifier<String?> problem = ValueNotifier(null);

  /// One ordered queue for load, add, remove, import and clear: operations
  /// never interleave, so an older save cannot land after a newer clear.
  Future<void> _tail = Future<void>.value();

  Future<T> _run<T>(Future<T> Function() fn) {
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return prev.then((_) => fn()).whenComplete(done.complete);
  }

  Future<File> _file() async => _fileProvider != null
      ? _fileProvider()
      : File(
          '${(await getApplicationDocumentsDirectory()).path}/routines.json',
        );

  /// Loads routines from disk. A read failure leaves the store unloaded so
  /// the next call retries; bad rows are skipped and reported in [problem].
  Future<void> load() => _run(_load);

  Future<void> _load() async {
    if (_loaded) return;
    final String raw;
    try {
      final file = await _file();
      if (!await file.exists()) {
        _loaded = true;
        problem.value = null;
        return;
      }
      raw = await _read(file);
    } catch (e) {
      debugPrint('RoutineStore read failed: $e');
      problem.value = 'Saved routines could not be read';
      return; // not loaded: a later load() retries
    }
    final good = <Routine>[];
    var skipped = false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        skipped = true;
      } else {
        for (final e in decoded) {
          final r = _parseStored(e);
          r == null ? skipped = true : good.add(r);
        }
      }
    } on FormatException {
      skipped = true;
    }
    _routines
      ..clear()
      ..addAll(good);
    _loaded = true;
    _incomplete = skipped;
    problem.value = skipped
        ? 'Some saved routines could not be read and were left untouched'
        : null;
  }

  static Routine? _parseStored(Object? e) {
    if (e is! Map) return null;
    final name = e['name'];
    final trigger = e['trigger'] ?? '';
    final instructions = e['instructions'] ?? '';
    final enabled = e['enabled'] ?? true;
    if (name is! String || name.isEmpty) return null;
    if (trigger is! String || instructions is! String) return null;
    if (enabled is! bool) return null;
    return Routine(
      name: name,
      trigger: trigger.toLowerCase(),
      instructions: instructions,
      enabled: enabled,
    );
  }

  /// Makes sure storage was read and is safe to rewrite, or throws.
  Future<void> _ensureWritable() async {
    await _load();
    if (!_loaded || _incomplete) {
      throw RoutineStoreException(
        problem.value ?? 'Saved routines are not available',
      );
    }
  }

  /// Persists the current list.
  Future<void> save() => _run(() async {
    await _ensureWritable();
    await _persist(_routines);
  });

  Future<void> _persist(List<Routine> list) async {
    try {
      await _write(list);
    } catch (e) {
      debugPrint('RoutineStore write failed: $e');
      throw const RoutineStoreException('Routines could not be saved');
    }
  }

  /// Deletes all routines, in memory and on disk (#83). Throws when the file
  /// could not be removed; memory is cleared only after the file is gone, so
  /// the two never disagree. This is also how an unreadable file is
  /// discarded on purpose.
  Future<void> clear() => _run(() async {
    try {
      final file = await _file();
      if (await file.exists()) await _delete(file);
    } catch (e) {
      debugPrint('RoutineStore clear failed: $e');
      throw const RoutineStoreException('Routines could not be deleted');
    }
    _routines.clear();
    _loaded = true;
    _incomplete = false;
    problem.value = null;
  });

  /// Adds (or replaces by name) and persists. Memory changes only after the
  /// write succeeds.
  Future<void> add(Routine routine) => _run(() async {
    await _ensureWritable();
    final next = [
      for (final r in _routines)
        if (r.name != routine.name) r,
      routine,
    ];
    await _persist(next);
    _routines
      ..clear()
      ..addAll(next);
  });

  /// Removes by name and persists; memory changes only after the write.
  Future<void> remove(String name) => _run(() async {
    await _ensureWritable();
    final next = [
      for (final r in _routines)
        if (r.name != name) r,
    ];
    await _persist(next);
    _routines
      ..clear()
      ..addAll(next);
  });

  /// The routine this utterance triggers, if any.
  Routine? match(String utterance) {
    final text = utterance.toLowerCase();
    for (final r in _routines) {
      if (r.enabled && r.trigger.isNotEmpty && text.contains(r.trigger)) {
        return r;
      }
    }
    return null;
  }

  /// Shareable skill pack: routines as portable JSON.
  String export() => jsonEncode(_routines.map((r) => r.toJson()).toList());

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
    final incoming = _parsePack(json); // pure; fails before queueing
    return _run(() => _applyImport(incoming));
  }

  int _stagingId = 0;

  /// Runs alone on the shared queue: collision check, snapshot, stage,
  /// commit and publication.
  Future<int> _applyImport(List<Routine> incoming) async {
    try {
      await _ensureWritable();
    } on RoutineStoreException {
      throw const RoutineImportException(
        'Saved routines could not be read, so nothing was imported',
      );
    }
    final taken = {for (final r in _routines) r.name};
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
    final next = [..._routines, ...incoming];
    try {
      await _write(next);
    } catch (e) {
      debugPrint('RoutineStore import write failed: $e');
      throw const RoutineImportException('Routines could not be saved');
    }
    _routines.addAll(incoming);
    return incoming.length;
  }

  /// Writes [list] to a same-directory staging file, then atomically
  /// replaces routines.json. A failure at either step leaves the original
  /// file untouched and removes the staging file.
  Future<void> _write(List<Routine> list) async {
    final target = await _file();
    final staging = File('${target.path}.${++_stagingId}.tmp');
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

/// Thrown when a routine change or deletion could not be completed; nothing
/// was changed. Messages are generic and never echo stored content.
class RoutineStoreException implements Exception {
  /// Creates the exception with a generic [message].
  const RoutineStoreException(this.message);

  /// Safe description of what failed.
  final String message;

  @override
  String toString() => message;
}
