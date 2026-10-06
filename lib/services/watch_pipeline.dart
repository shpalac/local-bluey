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

class WatchEvent {
  const WatchEvent({
    required this.kind,
    required this.at,
    required this.app,
    this.detail = '',
  });

  final WatchEventKind kind;
  final DateTime at;

  /// The allowlisted app this event is about (never an excluded one -
  /// excluded moments leave no trace beyond the session counter, #212).
  final String app;
  final String detail;
}

/// One cheap native signal read (#213): what is in front right now.
typedef FrontmostInfo = ({String app, String title, bool locked});

/// Injectable native signal source.
typedef FrontmostReader = Future<FrontmostInfo> Function();

/// Injectable frame differ: mean absolute difference 0..1 between the
/// current frame and the previous one (null on the first frame).
typedef FrameDiffFn = Future<double?> Function();

/// Injectable vision trigger (#213).
typedef VisionCall = Future<void> Function(String app, String detail);

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

  final FrontmostReader frontmost;
  final FrameDiffFn frameDiff;
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

  final List<WatchEvent> events = [];
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
    if (!_watch.isActive) return null;
    final info = await frontmost();
    return _watch.runIfAllowed<WatchEvent?>(
      frontApp: info.app,
      windowTitle: info.title,
      locked: info.locked,
      operation: () => _process(info),
    );
  }

  Future<WatchEvent?> _process(FrontmostInfo info) async {
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
      await onVision!(info.app, info.title);
      _emit(
        WatchEvent(
          kind: WatchEventKind.visionCall,
          at: _clock.now(),
          app: info.app,
          detail: info.title,
        ),
      );
    }
    return change;
  }

  WatchEvent _emit(WatchEvent event) {
    events.add(event);
    if (events.length > bufferCap) events.removeAt(0);
    _eventsController.add(event);
    return event;
  }

  /// Session trace ends here; wired to session stop (#212/#213).
  void clear() => events.clear();

  Future<void> dispose() => _eventsController.close();
}
