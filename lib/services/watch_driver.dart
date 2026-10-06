import 'dart:async';

import 'frame_differ.dart';
import 'screen_watch.dart';
import 'watch_pipeline.dart';

/// Drives pipeline ticks on an adaptive timer (#213): quiet screens back
/// off toward [maxInterval], activity speeds back up to [minInterval].
/// The driver lives only while a watch session is live; session stop (the
/// kill switch) cancels in-flight ticks and clears the event buffer.
class WatchDriver {
  WatchDriver({
    required this.pipeline,
    required this.differ,
    ScreenWatch? watch,
  }) : _watch = watch ?? ScreenWatch.instance;

  /// The pipeline being ticked.
  final WatchPipeline pipeline;

  /// The frame source whose activity level adapts the tick rate.
  final FrameDiffer differ;

  final ScreenWatch _watch;

  /// Fastest tick rate (active use).
  static const minInterval = Duration(seconds: 1);

  /// Slowest tick rate (idle screen).
  static const maxInterval = Duration(seconds: 5);

  Timer? _timer;
  bool _ticking = false;
  Duration _interval = minInterval;

  /// Whether the driver is ticking.
  bool get running => _timer != null;

  /// The current adaptive interval.
  Duration get interval => _interval;

  /// Starts ticking. Safe to call again on an already-running driver.
  void start() {
    if (_timer != null) return;
    _watch.registerInFlight(stop);
    _schedule(_interval);
  }

  /// Stops ticking and clears the session's buffered events (#212/#213).
  /// Registered as a session cancel listener, so it also fires from the
  /// one-tap stop within the same second.
  void stop() {
    _timer?.cancel();
    _timer = null;
    differ.reset();
    pipeline.clear();
    _interval = minInterval;
  }

  void _schedule(Duration after) {
    _timer?.cancel();
    _timer = Timer(after, _onTick);
  }

  Future<void> _onTick() async {
    if (_ticking) return; // a slow tick never overlaps the next
    _ticking = true;
    try {
      final event = await pipeline.tick();
      _interval = event != null
          ? minInterval
          : Duration(
              milliseconds: (_interval.inMilliseconds * 3 ~/ 2).clamp(
                minInterval.inMilliseconds,
                maxInterval.inMilliseconds,
              ),
            );
    } finally {
      _ticking = false;
    }
    if (!_watch.isActive) {
      stop();
      return;
    }
    _schedule(_interval);
  }
}
