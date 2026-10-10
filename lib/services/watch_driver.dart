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
    Future<WatchEvent?> Function()? tick,
  }) : _watch = watch ?? ScreenWatch.instance,
       _tick = tick ?? pipeline.tick;

  final Future<WatchEvent?> Function() _tick;

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
  bool _running = false;
  int _generation = 0;
  Duration _interval = minInterval;

  /// Whether a run is active, including an entered tick or restart draining
  /// stale work. A tick error stops the run until an explicit start.
  bool get running => _running;

  /// The current adaptive interval.
  Duration get interval => _interval;

  /// Starts ticking. Safe to call again on an already-running driver.
  void start() {
    if (_running || !_watch.isActive) return;
    _running = true;
    ++_generation;
    _watch.registerInFlight(stop);
    if (!_ticking) _schedule(_interval);
  }

  /// Stops ticking and clears the session's buffered events (#212/#213).
  /// Registered as a session cancel listener, so it also fires from the
  /// one-tap stop within the same second.
  void stop() {
    _running = false;
    ++_generation;
    _watch.unregisterInFlight(stop);
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

  // Errors stop this run explicitly; a later start can retry. No raw screen
  // or exception detail is retained, and no uncaught timer future escapes.
  Future<void> _onTick() async {
    _timer = null;
    if (!_running || _ticking) return;
    if (!_watch.isActive) {
      stop();
      return;
    }
    final gen = _generation;
    _ticking = true;
    try {
      final event = await _tick();
      if (gen != _generation || !_running) return;
      _interval = event != null
          ? minInterval
          : Duration(
              milliseconds: (_interval.inMilliseconds * 3 ~/ 2).clamp(
                minInterval.inMilliseconds,
                maxInterval.inMilliseconds,
              ),
            );
    } catch (_) {
      if (gen == _generation) stop();
    } finally {
      _ticking = false;
      if (gen != _generation) {
        // The old pipeline can settle after manual stop while session remains
        // active. No newer tick has entered yet, so discard its buffered trace.
        differ.reset();
        pipeline.clear();
      }
      if (_running && _watch.isActive) {
        _schedule(_interval);
      } else if (_running) {
        stop();
      }
    }
  }
}
