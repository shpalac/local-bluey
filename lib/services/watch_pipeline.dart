import 'dart:async';

import 'package:clock/clock.dart';

import 'screen_watch.dart';

/// What the watcher observed at one moment (#213).
enum WatchEventKind {
  /// Frontmost app or window title changed.
  appSwitch,

  /// Frame diff passed the meaningful-change threshold after debounce.
  meaningfulChange,

  /// A vision-model call fired (only after a meaningful change).
  visionCall,
}

/// One recorded pipeline moment (#213): what happened, when, for which
/// allowlisted app.
class WatchEvent {
  const WatchEvent({
    required this.kind,
    required this.at,
    required this.app,
    this.detail = '',
  });

  /// What happened (app change, frame changed, vision call, ...).
  final WatchEventKind kind;

  /// When it happened.
  final DateTime at;

  /// The allowlisted app this event is about (never an excluded one -
  /// excluded moments leave no trace beyond the session counter, #212).
  final String app;

  /// Optional extra info (e.g. the vision answer).
  final String detail;
}

/// One cheap native signal read (#213): what is in front right now.
typedef FrontmostInfo = ({String app, String title, bool locked});

/// Injectable native signal source.
typedef FrontmostReader = Future<FrontmostInfo> Function();

/// Injectable frame differ: mean absolute difference 0..1 between the
/// current frame and the previous one (null on the first frame).
typedef FrameDiffFn = Future<double?> Function();

/// Injectable vision trigger (#213). Returns a one-line summary used as
/// the event's evidence detail (#214); null means no summary.
typedef VisionCall = Future<String?> Function(String app, String detail);

/// Event-driven observation pipeline (#213). Cheap signals first; a frame
/// diff only when the app stays put; a vision call only when the diff says
/// the change is meaningful. Rolling in-memory buffer only - nothing
/// touches disk, and [clear] (wired to session stop) erases the session's
/// events. No keystroke logging, ever.
///
/// The frontmost-app read itself is the one signal the pipeline must have
/// to ENFORCE exclusions (#212); everything past it - diff, events, vision -
/// runs only inside [ScreenWatch.runIfAllowed], so an excluded app, private
/// window or lock screen pauses the pipeline and moves only the counter.
class WatchPipeline {
  WatchPipeline({
    required this.frontmost,
    required this.frameDiff,
    this.onVision,
    ScreenWatch? watch,
    Clock? clock,
  }) : _watch = watch ?? ScreenWatch.instance,
       _clockOverride = clock;

  /// Supplies the frontmost app (test seams in via the constructor).
  final FrontmostReader frontmost;

  /// Supplies frame-diff results between consecutive frames.
  final FrameDiffFn frameDiff;

  /// Optional vision-model call; when null, frames are only diffed.
  final VisionCall? onVision;
  final ScreenWatch _watch;
  final Clock? _clockOverride;

  Clock get _clock => _clockOverride ?? clock;

  /// Diff above this is a candidate "meaningful change" (#213).
  static const diffThreshold = 0.08;

  /// A candidate must hold for this many polls to count (debounce).
  static const debouncePolls = 2;

  /// Minimum gap between vision calls (budget back-off, #213).
  static const visionCooldown = Duration(seconds: 45);

  /// Rolling buffer cap; oldest events drop off (#213).
  static const bufferCap = 200;

  /// Rolling event buffer for the session trace UI (#213).
  final List<WatchEvent> _events = [];

  /// Immutable independent snapshot of the current capped session trace.
  List<WatchEvent> get events => List.unmodifiable(_events);

  /// Evidence longer than these UTF-16 code-unit limits stays silent, never
  /// truncated into a comparison collision. Raw display data is not interpreted.
  static const maxAppLength = 128;

  /// Maximum title or vision-summary code units retained in session evidence.
  static const maxDetailLength = 512;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _closing;
  final _eventsController = StreamController<WatchEvent>.broadcast();

  /// Event stream for the suggestion layer (#214).
  Stream<WatchEvent> get stream => _eventsController.stream;

  String? _lastApp;
  String? _lastTitle;
  int _changeStreak = 0;
  DateTime? _lastVisionAt;

  /// One pipeline tick: read cheap signals, then let the 212 gate decide
  /// whether any deeper work may run.
  Future<WatchEvent?> tick() async {
    if (_disposed || !_watch.isActive) return null;
    final gen = _generation;
    final session = _watch.generation;
    bool stale() =>
        _disposed ||
        gen != _generation ||
        session != _watch.generation ||
        !_watch.isActive;
    try {
      final info = await frontmost();
      if (stale()) return null;
      final result = await _watch.runIfAllowed<WatchEvent?>(
        frontApp: info.app,
        windowTitle: info.title,
        locked: info.locked,
        operation: () => _process(info, stale),
      );
      return stale() ? null : result;
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }

  Future<WatchEvent?> _process(
    FrontmostInfo info,
    bool Function() stale,
  ) async {
    if (stale()) return null;
    if (info.app.length > maxAppLength || info.title.length > maxDetailLength) {
      // Fail silent without retaining oversized strings as a baseline. The
      // next normal observation starts from a fresh comparison, not a prefix.
      _lastApp = _lastTitle = null;
      _changeStreak = 0;
      return null;
    }
    final switched = info.app != _lastApp || info.title != _lastTitle;
    _lastApp = info.app;
    _lastTitle = info.title;

    if (switched) {
      _changeStreak = 0;
      return _emit(
        WatchEvent(
          kind: WatchEventKind.appSwitch,
          at: _clock.now(),
          app: info.app,
          detail: info.title,
        ),
      );
    }

    // Signals quiet: check the frame itself. Typing/scrolling shows up as
    // small diffs below the threshold and never reaches a vision call.
    final diff = await frameDiff();
    if (stale()) return null;
    if (diff == null || diff < diffThreshold) {
      _changeStreak = 0;
      return null;
    }
    _changeStreak++;
    if (_changeStreak < debouncePolls) return null;
    _changeStreak = 0;

    final change = _emit(
      WatchEvent(
        kind: WatchEventKind.meaningfulChange,
        at: _clock.now(),
        app: info.app,
        detail: 'diff ${diff.toStringAsFixed(2)}',
      ),
    );

    final lastVision = _lastVisionAt;
    final cooledDown =
        lastVision == null ||
        _clock.now().difference(lastVision) >= visionCooldown;
    if (cooledDown && onVision != null) {
      _lastVisionAt = _clock.now();
      final summary = await onVision!(info.app, info.title);
      if (stale()) return null;
      if (summary != null && summary.length > maxDetailLength) return change;
      _emit(
        WatchEvent(
          kind: WatchEventKind.visionCall,
          at: _clock.now(),
          app: info.app,
          detail: summary ?? info.title,
        ),
      );
    }
    return change;
  }

  WatchEvent _emit(WatchEvent event) {
    _events.add(event);
    if (_events.length > bufferCap) _events.removeAt(0);
    _eventsController.add(event);
    return event;
  }

  /// Session trace ends here; wired to session stop (#212/#213).
  void clear() {
    _generation++;
    _events.clear();
    _lastApp = _lastTitle = null;
    _changeStreak = 0;
    _lastVisionAt = null;
  }

  /// Closes the event stream.
  Future<void> dispose() {
    if (_disposed) return _closing!;
    _disposed = true;
    clear();
    return _closing = _eventsController.close();
  }
}
