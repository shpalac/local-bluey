import 'dart:async';

import 'package:clock/clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'watch_context.dart';
import 'strings.dart';
import 'watch_policy.dart';
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
    this.observedDetail,
    this.repeatCount,
  });

  /// Original quoted screen data, never translated or interpreted.
  final String? observedDetail;

  /// Count used only for owned localized evidence framing.
  final int? repeatCount;

  /// Localizes only the built-in reason; unknown caller reasons remain data.
  String get localReason => observedDetail == null
      ? reason
      : Strings.t(
          'This keeps showing up on your screen',
          'זה מופיע שוב ושוב על המסך שלך',
        );

  /// Localized framing around unchanged untrusted screen content.
  String get localEvidence => observedDetail == null || repeatCount == null
      ? evidence
      : Strings.t(
          '"$observedDetail" in $app ($repeatCount times this session)',
          '"$observedDetail" ב-$app ($repeatCount פעמים בסשן הזה)',
        );

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
  WatchSuggestions({
    Clock? clock,
    Future<Set<String>> Function()? readNeverApps,
  }) : _clockOverride = clock,
       _readNeverApps = readNeverApps ?? neverApps;

  final Future<Set<String>> Function() _readNeverApps;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _disposal;

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

  /// Maximum retained repetition keys, evicted in first-in order.
  static const maxRepeatedKeys = 64;

  /// Maximum retained detail code units. Oversized events stay silent rather
  /// than merging distinct truncated prefixes into a false repeated trigger.
  static const maxDetailLength = 512;

  /// Maximum retained app display/identity code units.
  static const maxAppLength = 128;
  final Map<(String, String), int> _repeatedSummaries = {};

  /// Number of retained keys, exposed for deterministic bounded-state tests.
  int get retainedKeyCount => _repeatedSummaries.length;

  /// Apps the user said "never" to.
  static Future<Set<String>> neverApps() async =>
      ((await SharedPreferences.getInstance()).getStringList(_kNeverApps) ??
              const [])
          .map(WatchPolicy.normalize)
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
    if (_disposed) return;
    _generation++;
    _shownThisSession = 0;
    _lastShownAt = null;
    _repeatedSummaries.clear();
  }

  /// Feeds one event. Returns the suggestion if one was emitted.
  Future<WatchSuggestion?> onEvent(WatchEvent event) async {
    if (_disposed) return null;
    final gen = _generation;
    final displayApp = event.app.trim();
    final app = WatchPolicy.normalize(event.app);
    final detail = event.detail.trim();
    if (event.app.length > maxAppLength ||
        event.detail.length > maxDetailLength) {
      return null;
    }
    final canonical = WatchEvent(
      kind: event.kind,
      at: event.at,
      app: app,
      detail: detail,
    );
    final context = WatchContext.infer([canonical]);
    if (context == null || context.confidence < WatchContext.confidentEnough) {
      return null;
    }
    final Set<String> never;
    try {
      never = await _readNeverApps();
    } catch (_) {
      if (_disposed || gen != _generation) return null;
      rethrow;
    }
    if (_disposed || gen != _generation) return null;
    if (never.map(WatchPolicy.normalize).contains(app)) return null;
    if (_shownThisSession >= maxPerSession) return null;
    final lastShown = _lastShownAt;
    if (lastShown != null && _clock.now().difference(lastShown) < minGap) {
      return null;
    }

    // Trigger (first slice): the same problem text keeps showing up on
    // screen - e.g. a repeated terminal error or a form re-entered.
    if (event.kind != WatchEventKind.visionCall || detail.isEmpty) {
      return null;
    }
    final normalized = (app, detail.toLowerCase());
    if (!_repeatedSummaries.containsKey(normalized) &&
        _repeatedSummaries.length >= maxRepeatedKeys) {
      _repeatedSummaries.remove(_repeatedSummaries.keys.first);
    }
    final count = (_repeatedSummaries[normalized] ?? 0) + 1;
    _repeatedSummaries[normalized] = count;
    if (count < repeatTriggerCount) return null;
    _repeatedSummaries.remove(normalized);

    _shownThisSession++;
    _lastShownAt = _clock.now();
    // The bounded evidence is quoted as DATA. It is displayed to the
    // user exactly because screen text can lie; nothing here acts on it.
    final suggestion = WatchSuggestion(
      reason: 'This keeps showing up on your screen',
      evidence:
          '"${event.detail}" in $displayApp '
          '($count times this session)',
      app: displayApp,
      observedDetail: event.detail,
      repeatCount: count,
      at: _clock.now(),
    );
    _controller.add(suggestion);
    return suggestion;
  }

  /// Closes the suggestion stream.
  Future<void> dispose() {
    if (_disposed) return _disposal!;
    _disposed = true;
    _generation++;
    _repeatedSummaries.clear();
    return _disposal = _controller.close();
  }
}
