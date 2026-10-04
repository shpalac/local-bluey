import 'package:shared_preferences/shared_preferences.dart';

import 'conversation.dart';
import 'routines.dart';

/// Discovery, recents, and local search (#93). Everything is derived from
/// data already stored locally; nothing reads the screen.
class Discover {
  Discover._();

  /// Rule-based suggestions from context the app already owns (#93).
  /// Screen contents are never read - suggestions stay privacy-safe.
  static List<String> suggestions({
    required bool awake,
    required int routineCount,
    required int recentCount,
  }) {
    final out = <String>[];
    if (!awake) out.add('Wake Bluey and ask for anything');
    if (routineCount == 0) out.add('Create your first routine');
    if (recentCount == 0) out.add('Try: "summarize my day"');
    out.add('Hold to talk from your phone');
    return out.take(3).toList();
  }

  /// Recent user requests, newest first - a mirror of the local
  /// conversation log, so clearing data (#83) clears these too (#93).
  static List<String> recentRequests({int limit = 10}) => ConversationStore
      .instance
      .entries
      .where((e) => e.role == 'user')
      .map((e) => e.text)
      .toList()
      .reversed
      .take(limit)
      .toList();

  /// Offline search over locally stored answers and routines only (#93).
  static List<String> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits = <String>[
      for (final e in ConversationStore.instance.entries)
        if (e.text.toLowerCase().contains(q)) e.text,
      for (final r in RoutineStore.instance.routines)
        if (r.name.toLowerCase().contains(q)) r.name,
    ];
    return hits;
  }
}

/// Notification opt-ins (#93): every type defaults to OFF.
class NotificationPrefs {
  NotificationPrefs._();
  static final NotificationPrefs instance = NotificationPrefs._();

  static const _types = {'routineFinished', 'pairRequest'};
  static const _kPrefix = 'notify.';

  Future<bool> enabled(String type) async {
    assert(_types.contains(type));
    return (await SharedPreferences.getInstance()).getBool('$_kPrefix$type') ??
        false; // default off (#93)
  }

  Future<void> setEnabled(String type, bool value) async {
    assert(_types.contains(type));
    await (await SharedPreferences.getInstance()).setBool(
      '$_kPrefix$type',
      value,
    );
  }
}
