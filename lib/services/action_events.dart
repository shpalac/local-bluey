import 'watch_pipeline.dart';

/// Stable kind of a normalized action event (BLU-006). Deliberately smaller
/// than [WatchEventKind]: consumers see what happened, not how it was sensed.
enum ActionEventKind {
  /// The frontmost app or window changed.
  appActivated,

  /// The frame changed meaningfully while the app stayed in front.
  screenChanged,

  /// A vision call ran after a meaningful change.
  screenDescribed,
}

/// One normalized, content-free action event.
///
/// It carries no window title, vision summary or any other screen text on
/// purpose: later layers (pattern mining, suggestions) get the app, the kind,
/// the time and a fixed confidence, and nothing that could hold a secret.
class ActionEvent {
  const ActionEvent({
    required this.sequence,
    required this.sessionId,
    required this.kind,
    required this.app,
    required this.at,
    required this.confidence,
  });

  /// 0-based position in the normalizer's accepted stream; never reused.
  final int sequence;

  /// Session this event belongs to; changes on a long gap or [endSession].
  final int sessionId;

  /// What happened.
  final ActionEventKind kind;

  /// Allowlisted app the event is about.
  final String app;

  /// When it happened, as reported by the source event.
  final DateTime at;

  /// Fixed per-kind weight in 0..1. A deterministic rule, not a statistic.
  final double confidence;

  @override
  String toString() =>
      'ActionEvent(#$sequence s$sessionId ${kind.name} $app $confidence)';
}

/// Pure, in-memory mapping from [WatchEvent]s to [ActionEvent]s (BLU-006).
///
/// Nothing is persisted, nothing leaves the process, and the module is not
/// wired into the app, so it adds no behavior until a later change uses it.
/// The allowlist is asked again here (fail closed): an event for an app that
/// is not allowed right now is dropped and leaves no trace.
class ActionEventNormalizer {
  ActionEventNormalizer({
    required this.isAppAllowed,
    this.debounce = const Duration(seconds: 2),
    this.sessionGap = const Duration(minutes: 10),
    this.maxEvents = 200,
  }) {
    if (debounce.isNegative) {
      throw ArgumentError.value(debounce, 'debounce', 'must not be negative');
    }
    if (sessionGap.isNegative) {
      throw ArgumentError.value(
        sessionGap,
        'sessionGap',
        'must not be negative',
      );
    }
    if (maxEvents < 1) {
      throw ArgumentError.value(maxEvents, 'maxEvents', 'must be at least 1');
    }
  }

  /// Current allowlist decision for an app name. A throwing callback drops
  /// the event (fail closed).
  final bool Function(String app) isAppAllowed;

  /// Same kind for the same app inside this window is one event, even when
  /// events for other apps or kinds arrive in between (per-key debounce).
  final Duration debounce;

  /// Silence longer than this starts a new session.
  final Duration sessionGap;

  /// Retained event cap; the oldest events drop off.
  final int maxEvents;

  /// Fixed confidence per kind:
  /// an app switch is a direct signal, a frame diff is the weakest.
  static const confidenceByKind = {
    ActionEventKind.appActivated: 0.9,
    ActionEventKind.screenChanged: 0.6,
    ActionEventKind.screenDescribed: 0.7,
  };

  final List<ActionEvent> _events = [];
  int _sequence = 0;
  int _session = 0;
  DateTime? _lastAt;
  bool _ended = false;

  /// Last accepted time per (kind, app). Bounded: entries older than the
  /// debounce window are pruned on every accepted event, and the map is
  /// emptied by [endSession] and [clear].
  final Map<(ActionEventKind, String), DateTime> _lastByKey = {};

  /// Independent snapshot of the retained events.
  List<ActionEvent> get events => List.unmodifiable(_events);

  /// Current session id.
  int get sessionId => _session;

  /// Maps one source event, or returns null when it is dropped: empty or
  /// oversized app, app not allowed, a timestamp that goes backwards, or a
  /// duplicate (same kind and app) inside the debounce window.
  ///
  /// Calling [endSession] and then sending an event after a long gap still
  /// advances the session only once.
  ActionEvent? normalize(WatchEvent source) {
    final app = source.app;
    if (app.isEmpty || app.length > WatchPipeline.maxAppLength) return null;
    var allowed = false;
    try {
      allowed = isAppAllowed(app);
    } catch (_) {
      allowed = false;
    }
    if (!allowed) return null;
    final last = _lastAt;
    if (last != null && source.at.isBefore(last)) return null;
    final kind = switch (source.kind) {
      WatchEventKind.appSwitch => ActionEventKind.appActivated,
      WatchEventKind.meaningfulChange => ActionEventKind.screenChanged,
      WatchEventKind.visionCall => ActionEventKind.screenDescribed,
    };
    final prev = _lastByKey[(kind, app)];
    if (prev != null && source.at.difference(prev) < debounce) return null;
    // After endSession the session already advanced; do not advance twice.
    if (!_ended && last != null && source.at.difference(last) > sessionGap) {
      _session++;
    }
    _ended = false;
    final event = ActionEvent(
      sequence: _sequence++,
      sessionId: _session,
      kind: kind,
      app: app,
      at: source.at,
      confidence: confidenceByKind[kind]!,
    );
    _lastAt = source.at;
    _lastByKey.removeWhere((_, at) => source.at.difference(at) >= debounce);
    _lastByKey[(kind, app)] = source.at;
    _events.add(event);
    if (_events.length > maxEvents) _events.removeAt(0);
    return event;
  }

  /// Ends the current session now (stop, pause or lock): the next accepted
  /// event starts a new session and is never debounced against older ones.
  void endSession() {
    _session++;
    _ended = true;
    _lastByKey.clear();
  }

  /// Forgets every retained event and starts over, as after a restart.
  void clear() {
    _events.clear();
    _sequence = 0;
    _session = 0;
    _lastAt = null;
    _ended = false;
    _lastByKey.clear();
  }

  /// Normalizes a source stream. Cancelling the returned subscription stops
  /// everything; there is no background work.
  Stream<ActionEvent> bind(Stream<WatchEvent> source) =>
      source.map(normalize).where((event) => event != null).cast<ActionEvent>();
}
