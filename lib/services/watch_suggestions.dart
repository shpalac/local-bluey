import 'dart:async';

import 'package:clock/clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'watch_context.dart';
import 'watch_pipeline.dart';

/// A read-only, screen-aware suggestion (#214). It never does anything:
/// it shows the reason and the evidence it was derived from, and the user
/// dismisses it in one tap.
class WatchSuggestion {
  const WatchSuggestion({
    required this.reason,
    required this.evidence,
    required this.app,
    required this.at,
  });

  /// Why this is worth the interruption, in plain language.
  final String reason;

  /// What the watcher saw, quoted as data - never parsed, never followed.
  final String evidence;

  /// The allowlisted app that triggered it.
  final String app;

  /// When it fired.
  final DateTime at;
}

/// Relevance and interruption policy for screen-aware suggestions (#214).
///
/// Quiet by default: few triggers, hard rate limits, per-app "never",
/// and anything uncertain stays silent. Screen text is UNTRUSTED DATA -
/// it is quoted as evidence and shown; nothing in this layer can hand it
/// to a tool or treat it as an instruction.
class WatchSuggestions {
  WatchSuggestions({Clock? clock}) : _clockOverride = clock;

  final Clock? _clockOverride;
  Clock get _clock => _clockOverride ?? clock;

  /// Hard caps (#214: quiet by default).
  static const maxPerSession = 3;

  /// Minimum time between two suggestions.
  static const minGap = Duration(minutes: 3);

  /// How many times the same trigger must repeat before it fires.
  static const repeatTriggerCount = 3;

  static const _kNeverApps = 'watch.suggestNeverApps';

  final _controller = StreamController<WatchSuggestion>.broadcast();

  /// Suggestion stream for the UI.
  Stream<WatchSuggestion> get stream => _controller.stream;

  int _shownThisSession = 0;
  DateTime? _lastShownAt;
  final Map<String, int> _repeatedSummaries = {};

  /// Apps the user said "never" to.
  static Future<Set<String>> neverApps() async =>
      ((await SharedPreferences.getInstance()).getStringList(_kNeverApps) ??
              const [])
          .map((a) => a.toLowerCase())
          .toSet();

  /// Persists a per-app "never suggest" choice.
  static Future<void> neverForApp(String app) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [...?prefs.getStringList(_kNeverApps)];
    final n = app.trim().toLowerCase();
    if (n.isEmpty || list.contains(n)) return;
    list.add(n);
    await prefs.setStringList(_kNeverApps, list);
  }

  /// Session lifecycle: counters reset with each new session.
  void resetSession() {
    _shownThisSession = 0;
    _lastShownAt = null;
    _repeatedSummaries.clear();
  }

  /// Feeds one event. Returns the suggestion if one was emitted.
  Future<WatchSuggestion?> onEvent(WatchEvent event) async {
    final context = WatchContext.infer([event]);
    if (context == null || context.confidence < WatchContext.confidentEnough) {
      return null;
    }
    if (await neverApps().then(
      (apps) => apps.contains(context.app.toLowerCase()),
    )) {
      return null;
    }
    if (_shownThisSession >= maxPerSession) return null;
    final lastShown = _lastShownAt;
    if (lastShown != null && _clock.now().difference(lastShown) < minGap) {
      return null;
    }

    // Trigger (first slice): the same problem text keeps showing up on
    // screen - e.g. a repeated terminal error or a form re-entered.
    if (event.kind != WatchEventKind.visionCall || event.detail.isEmpty) {
      return null;
    }
    final normalized = event.detail.trim().toLowerCase();
    final count = (_repeatedSummaries[normalized] ?? 0) + 1;
    _repeatedSummaries[normalized] = count;
    if (count < repeatTriggerCount) return null;
    _repeatedSummaries.remove(normalized);

    _shownThisSession++;
    _lastShownAt = _clock.now();
    // The evidence is quoted verbatim as DATA. It is displayed to the
    // user exactly because screen text can lie; nothing here acts on it.
    final suggestion = WatchSuggestion(
      reason: 'This keeps showing up on your screen',
      evidence:
          '"${event.detail}" in ${event.app} '
          '($count times this session)',
      app: event.app,
      at: _clock.now(),
    );
    _controller.add(suggestion);
    return suggestion;
  }

  /// Closes the suggestion stream.
  Future<void> dispose() => _controller.close();
}
