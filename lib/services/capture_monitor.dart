import 'package:flutter/foundation.dart';

import 'screen_watch.dart';
import 'watch_policy.dart';

/// What the capture indicator shows (BLU-007).
enum CaptureIndicator {
  /// No watching session: nothing is observed.
  off,

  /// A session is running and observation may happen.
  active,

  /// A session is running but the user paused observation.
  paused,
}

/// Why an observation was refused (BLU-007). Counters only: no app names,
/// titles or screen content are ever recorded.
enum CaptureRefusal {
  /// Paused by the user.
  paused,

  /// The app is not on this session's allowlist, or the session no longer
  /// holds (policy tightened, local-only turned off, time ran out).
  notAllowed,

  /// A hard-denied app was in front.
  hardDenied,

  /// A private browser window was in front.
  privateWindow,

  /// The screen was locked.
  locked,
}

/// Session indicator, pause/resume, refusal counters and immediate stop on
/// top of [ScreenWatch] (BLU-007).
///
/// It never starts a session: [resume] only lifts a pause inside a session
/// that is already running, and a stopped session forgets its pause, so
/// nothing is ever enabled silently. All state is in memory, so after a
/// restart the indicator is [CaptureIndicator.off] by construction. The
/// counters hold only integers.
class CaptureMonitor extends ChangeNotifier {
  CaptureMonitor({ScreenWatch? watch})
    : _watch = watch ?? ScreenWatch.instance {
    _wasActive = _watch.isActive;
    _watch.addListener(_onWatchChanged);
  }

  final ScreenWatch _watch;
  bool _paused = false;
  late bool _wasActive;
  bool _disposed = false;

  /// Bumped on every pause, resume, stop, session change and dispose. A
  /// request captures it before its first gate; if it moved, the request is
  /// refused or its result is dropped.
  int _epoch = 0;
  final Map<CaptureRefusal, int> _counts = {
    for (final r in CaptureRefusal.values) r: 0,
  };
  Listenable? _lock;
  bool Function()? _isLocked;

  /// What the indicator should show right now.
  CaptureIndicator get indicator => !_watch.isActive
      ? CaptureIndicator.off
      : _paused
      ? CaptureIndicator.paused
      : CaptureIndicator.active;

  /// Whether observation is paused inside a running session.
  bool get paused => _paused && _watch.isActive;

  /// Independent snapshot of the refusal counters.
  Map<CaptureRefusal, int> get refusals => Map.unmodifiable(_counts);

  /// Pauses observation. Returns false (and does nothing) with no session.
  bool pause() {
    if (_disposed || !_watch.isActive || _paused) return false;
    _paused = true;
    _epoch++;
    notifyListeners();
    return true;
  }

  /// Lifts a pause. Returns false with no session: it never starts one.
  bool resume() {
    if (_disposed || !_watch.isActive || !_paused) return false;
    _paused = false;
    _epoch++;
    notifyListeners();
    return true;
  }

  /// Immediate stop; also forgets the pause.
  ///
  /// Stays effective after [dispose] (stopping is the safe direction) but
  /// then notifies nobody.
  void stop() {
    _epoch++;
    _watch.stop();
    _clearPause();
  }

  /// Stops capture whenever [isLocked] reports true after [lock] notifies,
  /// and right now if it is already locked. Replaces an earlier attachment.
  ///
  /// Does nothing after [dispose]: no listener is attached to a dead monitor.
  void attachLock(Listenable lock, bool Function() isLocked) {
    if (_disposed) return;
    detachLock();
    _lock = lock;
    _isLocked = isLocked;
    lock.addListener(_onLockChanged);
    _onLockChanged();
  }

  /// Stops listening to the lock.
  void detachLock() {
    _lock?.removeListener(_onLockChanged);
    _lock = null;
    _isLocked = null;
  }

  void _onLockChanged() {
    final isLocked = _isLocked;
    if (isLocked == null) return;
    var locked = true; // A throwing check fails closed.
    try {
      locked = isLocked();
    } catch (_) {}
    if (locked && _watch.isActive) {
      _bump(CaptureRefusal.locked);
      stop();
    }
  }

  void _onWatchChanged() {
    if (_disposed) return;
    final active = _watch.isActive;
    if (active == _wasActive) return;
    _wasActive = active;
    _epoch++;
    // The indicator changed on a normal off<->active transition: tell
    // listeners once, and forget any pause when the session ended.
    if (!active) _paused = false;
    notifyListeners();
  }

  void _clearPause() {
    if (_paused) {
      _paused = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _bump(CaptureRefusal reason) {
    _counts[reason] = _counts[reason]! + 1;
    if (!_disposed) notifyListeners();
  }

  /// Like [ScreenWatch.runIfAllowed], plus the pause and the refusal
  /// counters. Returns null when refused or when stopped, paused, restarted
  /// or disposed meanwhile.
  ///
  /// The monitor epoch and the [ScreenWatch] generation are captured before
  /// the first gate and checked again before the operation starts and before
  /// its result is returned, so a request that began in an older session or
  /// before a pause can neither start nor return a result. Pausing while an
  /// operation is running drops that operation's result (the operation itself
  /// cannot be cancelled from here).
  ///
  /// Refusal reasons are best effort: the watch is asked twice (here and
  /// inside [ScreenWatch.runIfAllowed]); a denial by the second ask is
  /// counted as [CaptureRefusal.notAllowed] without a finer reason.
  Future<T?> runIfAllowed<T>({
    required String frontApp,
    String? windowTitle,
    bool locked = false,
    required Future<T> Function() operation,
  }) async {
    if (_disposed || !_watch.isActive) return null;
    if (_paused) {
      _bump(CaptureRefusal.paused);
      return null;
    }
    final epoch = _epoch;
    final generation = _watch.generation;
    bool stale() =>
        _disposed ||
        _epoch != epoch ||
        _watch.generation != generation ||
        !_watch.isActive;
    final verdict = await _watch.mayObserve(
      frontApp: frontApp,
      windowTitle: windowTitle,
      locked: locked,
    );
    if (_disposed) return null;
    if (verdict != WatchVerdict.allow) {
      // Counted even if the denial itself ended the session (policy change
      // during the gate invalidates it): the refusal really happened.
      _bump(switch (verdict) {
        WatchVerdict.hardDenied => CaptureRefusal.hardDenied,
        WatchVerdict.privateWindow => CaptureRefusal.privateWindow,
        WatchVerdict.locked => CaptureRefusal.locked,
        _ => CaptureRefusal.notAllowed,
      });
      return null;
    }
    if (stale()) return null;
    var entered = false;
    final result = await _watch
        .runIfAllowed<T>(
          frontApp: frontApp,
          windowTitle: windowTitle,
          locked: locked,
          operation: () {
            if (stale() || _paused) {
              throw const _Fenced();
            }
            entered = true;
            return operation();
          },
        )
        .then<T?>(
          (v) => v,
          onError: (Object e) {
            if (e is _Fenced) return null;
            throw e;
          },
        );
    if (stale() || _paused) return null;
    if (result == null && !entered) _bump(CaptureRefusal.notAllowed);
    return result;
  }

  /// Clears the refusal counters.
  void resetRefusals() {
    if (_disposed) return;
    for (final r in CaptureRefusal.values) {
      _counts[r] = 0;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    detachLock();
    _watch.removeListener(_onWatchChanged);
    super.dispose();
  }
}

/// Thrown inside the guarded operation when the request went stale before it
/// started; caught in [CaptureMonitor.runIfAllowed], never escapes.
class _Fenced implements Exception {
  const _Fenced();
}
