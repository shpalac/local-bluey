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
    notifyListeners();
    return true;
  }

  /// Lifts a pause. Returns false with no session: it never starts one.
  bool resume() {
    if (_disposed || !_watch.isActive || !_paused) return false;
    _paused = false;
    notifyListeners();
    return true;
  }

  /// Immediate stop; also forgets the pause.
  void stop() {
    _watch.stop();
    _clearPause();
  }

  /// Stops capture whenever [isLocked] reports true after [lock] notifies,
  /// and right now if it is already locked. Replaces an earlier attachment.
  void attachLock(Listenable lock, bool Function() isLocked) {
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
    final active = _watch.isActive;
    if (_wasActive && !active) _clearPause();
    _wasActive = active;
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
  /// counters. Returns null when refused or when stopped meanwhile.
  Future<T?> runIfAllowed<T>({
    required String frontApp,
    String? windowTitle,
    bool locked = false,
    required Future<T> Function() operation,
  }) async {
    if (!_watch.isActive) return null;
    if (_paused) {
      _bump(CaptureRefusal.paused);
      return null;
    }
    final verdict = await _watch.mayObserve(
      frontApp: frontApp,
      windowTitle: windowTitle,
      locked: locked,
    );
    if (verdict != WatchVerdict.allow) {
      if (_watch.isActive) {
        _bump(switch (verdict) {
          WatchVerdict.hardDenied => CaptureRefusal.hardDenied,
          WatchVerdict.privateWindow => CaptureRefusal.privateWindow,
          WatchVerdict.locked => CaptureRefusal.locked,
          _ => CaptureRefusal.notAllowed,
        });
      }
      return null;
    }
    if (_paused) {
      _bump(CaptureRefusal.paused);
      return null;
    }
    return _watch.runIfAllowed<T>(
      frontApp: frontApp,
      windowTitle: windowTitle,
      locked: locked,
      operation: operation,
    );
  }

  /// Clears the refusal counters.
  void resetRefusals() {
    for (final r in CaptureRefusal.values) {
      _counts[r] = 0;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    detachLock();
    _watch.removeListener(_onWatchChanged);
    super.dispose();
  }
}
