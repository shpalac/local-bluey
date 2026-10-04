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

  final String name;

  /// Lowercase phrase matched against the user's utterance.
  final String trigger;

  /// What the brain should do when the trigger fires.
  final String instructions;
  final bool enabled;

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

class RoutineStore {
  RoutineStore._();
  static final RoutineStore instance = RoutineStore._();

  final List<Routine> routines = [];
  bool _loaded = false;

  Future<File> _file() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/routines.json');

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

  Future<void> add(Routine routine) async {
    routines.removeWhere((r) => r.name == routine.name);
    routines.add(routine);
    await save();
  }

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

  Future<int> importFrom(String json) async {
    final list = List<dynamic>.from(jsonDecode(json) as List);
    var added = 0;
    for (final e in list) {
      final routine = Routine.fromJson(Map<String, dynamic>.from(e as Map));
      if (routine.name.isEmpty || routine.trigger.isEmpty) continue;
      await add(routine);
      added++;
    }
    return added;
  }
}
