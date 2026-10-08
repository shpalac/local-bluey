/// Pure state machine for the global hold-to-talk key (#228).
///
/// The native key listener feeds it raw key events with timestamps; it
/// answers with what the recorder should do. It owns no timers and no
/// platform code, so every rule is unit tested with fake times. The caller
/// polls [HoldKeyMachine.tick] (for example every 50 ms) while a key is down.
library;

/// Keys the shortcut can use, plus [other] for any key that is not the
/// configured one (including other modifiers).
enum HoldKey { rightCommand, leftCommand, rightOption, fn, other }

/// What the recorder should do after an event.
enum HoldKeyAction {
  /// Nothing to do.
  none,

  /// Start recording: the key was held alone long enough.
  start,

  /// Stop recording and send what was said.
  send,

  /// Stop recording and throw it away.
  cancel,
}

/// Where the machine is in the hold.
enum HoldKeyState {
  /// No hold in progress.
  idle,

  /// The key is down but the threshold has not passed yet.
  pressed,

  /// Recording is running.
  recording,

  /// The hold was cancelled or disqualified; ignore everything until the
  /// key is released.
  blocked,
}

/// Decides when a held key becomes a recording, a send or a cancel.
class HoldKeyMachine {
  /// Creates a machine for [key]. A hold shorter than [threshold] is ignored.
  /// A recording longer than [maxRecording] is sent and the hold blocked, so
  /// a stuck key cannot keep the microphone open (#117).
  HoldKeyMachine({
    this.key = HoldKey.rightCommand,
    this.threshold = const Duration(milliseconds: 400),
    this.maxRecording = const Duration(minutes: 2),
  }) : assert(key != HoldKey.other, 'configure a concrete key');

  /// The configured trigger key.
  final HoldKey key;

  /// How long the key must be held alone before recording starts.
  final Duration threshold;

  /// Hard cap on one recording.
  final Duration maxRecording;

  HoldKeyState _state = HoldKeyState.idle;
  DateTime _since = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _recordingSince = DateTime.fromMillisecondsSinceEpoch(0);

  /// Current state, for the listening indicator and tests.
  HoldKeyState get state => _state;

  /// A key went down. Auto-repeat of the trigger key is ignored.
  HoldKeyAction keyDown(HoldKey pressed, DateTime now) {
    if (pressed == key) {
      if (_state == HoldKeyState.idle) {
        _state = HoldKeyState.pressed;
        _since = now;
      }
      return HoldKeyAction.none;
    }
    return _disqualify();
  }

  /// A key came up.
  HoldKeyAction keyUp(HoldKey released, DateTime now) {
    if (released != key) return HoldKeyAction.none;
    final was = _state;
    _state = HoldKeyState.idle;
    return was == HoldKeyState.recording
        ? HoldKeyAction.send
        : HoldKeyAction.none;
  }

  /// Esc cancels a pending or running hold without sending.
  HoldKeyAction escape(DateTime now) => _disqualify();

  /// Time passed with no event. Starts recording once the threshold is
  /// reached and ends one that ran past [maxRecording].
  HoldKeyAction tick(DateTime now) {
    if (_state == HoldKeyState.pressed && now.difference(_since) >= threshold) {
      _state = HoldKeyState.recording;
      _recordingSince = now;
      return HoldKeyAction.start;
    }
    if (_state == HoldKeyState.recording &&
        now.difference(_recordingSince) >= maxRecording) {
      _state = HoldKeyState.blocked;
      return HoldKeyAction.send;
    }
    return HoldKeyAction.none;
  }

  /// Sleep, lock, app deactivate, the kill switch or a lost key-up: stop
  /// everything. A running recording is cancelled, never sent.
  HoldKeyAction reset() {
    final was = _state;
    _state = HoldKeyState.idle;
    return was == HoldKeyState.recording
        ? HoldKeyAction.cancel
        : HoldKeyAction.none;
  }

  HoldKeyAction _disqualify() {
    final was = _state;
    if (was == HoldKeyState.idle) return HoldKeyAction.none;
    _state = HoldKeyState.blocked;
    return was == HoldKeyState.recording
        ? HoldKeyAction.cancel
        : HoldKeyAction.none;
  }
}
