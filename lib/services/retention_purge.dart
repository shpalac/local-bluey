import 'data_registry.dart';

/// How a registered store may be treated by a scoped purge (BLU-005).
enum RetentionClass {
  /// Never purged here: routines, settings, connections and anything not
  /// classified. This is the default, so an unlisted store fails closed.
  protected,

  /// Readable activity data the user may delete on its own.
  activity,

  /// Rebuildable cache the user may delete on its own.
  cache,
}

/// One row of the retention overview. Text only, no stored content.
class RetentionRow {
  const RetentionRow({
    required this.id,
    required this.whatEn,
    required this.retentionEn,
    required this.purgeable,
  });

  final String id;
  final String whatEn;

  /// The retention text exactly as the owning store declares it.
  final String retentionEn;

  /// Whether a scoped purge may delete it.
  final bool purgeable;
}

/// Outcome of a purge. Ids and short reasons only.
class PurgeResult {
  const PurgeResult({
    this.purged = const [],
    this.refused = const {},
    this.failed = const {},
  });

  /// Ids whose data was cleared.
  final List<String> purged;

  /// Ids not touched, with a reason: unknown, protected or busy.
  final Map<String, String> refused;

  /// Ids whose clear threw, with the exception type only.
  final Map<String, String> failed;

  bool get ok => refused.isEmpty && failed.isEmpty;
}

/// A purge entry: a store id, its classification and how to clear it.
class RetentionTarget {
  const RetentionTarget({
    required this.id,
    required this.whatEn,
    required this.retentionEn,
    required this.cls,
    required this.clear,
  });

  final String id;
  final String whatEn;
  final String retentionEn;
  final RetentionClass cls;
  final Future<void> Function() clear;
}

/// Scoped purge over a list of stores (BLU-005).
///
/// Pure orchestration, not wired into the app and with no storage of its
/// own. It decides nothing about retention periods: it shows the text each
/// store declares and deletes only stores the caller classified as
/// [RetentionClass.activity] or [RetentionClass.cache]. Everything else,
/// including every unclassified store, is refused and left alone, so the
/// "delete activity and caches" action cannot touch them. That guarantee is
/// conditional: it assumes a trusted caller. A caller that classifies a
/// routines or settings store as activity or cache can purge it, because this
/// module makes no classification or product-default choice of its own.
class RetentionPurger {
  RetentionPurger(Iterable<RetentionTarget> targets)
    : _targets = _index(targets);

  /// Builds targets from the registry. A store without an entry in
  /// [classes] is [RetentionClass.protected].
  factory RetentionPurger.fromRegistry(
    Iterable<DataStoreInfo> stores, {
    required Map<String, RetentionClass> classes,
  }) => RetentionPurger([
    for (final s in stores)
      RetentionTarget(
        id: s.id,
        whatEn: s.whatEn,
        retentionEn: s.retentionEn,
        cls: classes[s.id] ?? RetentionClass.protected,
        clear: s.clear,
      ),
  ]);

  final Map<String, RetentionTarget> _targets;
  bool _busy = false;

  static Map<String, RetentionTarget> _index(Iterable<RetentionTarget> list) {
    final map = <String, RetentionTarget>{};
    for (final t in list) {
      if (map.containsKey(t.id)) {
        throw ArgumentError('duplicate store id: ${t.id}');
      }
      map[t.id] = t;
    }
    return Map.unmodifiable(map);
  }

  /// True while a purge is running.
  bool get busy => _busy;

  /// What is stored and for how long, in registration order.
  List<RetentionRow> get overview => List.unmodifiable([
    for (final t in _targets.values)
      RetentionRow(
        id: t.id,
        whatEn: t.whatEn,
        retentionEn: t.retentionEn,
        purgeable: t.cls != RetentionClass.protected,
      ),
  ]);

  /// Clears the named stores, one at a time. Unknown and protected ids are
  /// refused. A second call while one is running refuses every id as busy
  /// and does nothing. A store that throws is reported and the rest still
  /// run. Repeated ids are cleared once.
  Future<PurgeResult> purge(Iterable<String> ids) async {
    final wanted = <String>{...ids};
    if (_busy) {
      return PurgeResult(refused: {for (final id in wanted) id: 'busy'});
    }
    _busy = true;
    try {
      final purged = <String>[];
      final refused = <String, String>{};
      final failed = <String, String>{};
      for (final id in wanted) {
        final t = _targets[id];
        if (t == null) {
          refused[id] = 'unknown';
        } else if (t.cls == RetentionClass.protected) {
          refused[id] = 'protected';
        } else {
          try {
            await t.clear();
            purged.add(id);
          } catch (e) {
            failed[id] = e.runtimeType.toString();
          }
        }
      }
      return PurgeResult(purged: purged, refused: refused, failed: failed);
    } finally {
      _busy = false;
    }
  }

  /// Clears every activity and cache store, nothing else.
  Future<PurgeResult> deleteActivityAndCaches() => purge([
    for (final t in _targets.values)
      if (t.cls != RetentionClass.protected) t.id,
  ]);
}
