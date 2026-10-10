import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First-success tutorial (#176): three real interactions right after
/// onboarding - wake Bluey, ask him something, watch him point. Each step
/// completes only on the real event (not on a button press), every step
/// can be skipped, and the whole thing replays from Settings.
enum TutorialStep { wake, ask, point }

/// Narrow done-flag persistence seam for deterministic controller fixtures.
abstract interface class TutorialDoneStore {
  /// Persists current-run completion or throws on failure.
  Future<void> markDone();

  /// Removes persisted completion or throws on failure.
  Future<void> clear();
}

class _PreferenceDoneStore implements TutorialDoneStore {
  _PreferenceDoneStore(this.prefs);
  final SharedPreferences? prefs;
  Future<SharedPreferences> get _prefs async =>
      prefs ?? await SharedPreferences.getInstance();
  @override
  Future<void> markDone() async {
    if (!await (await _prefs).setBool('tutorial.done', true)) {
      throw StateError('Tutorial storage failed.');
    }
  }

  @override
  Future<void> clear() async {
    if (!await (await _prefs).remove('tutorial.done')) {
      throw StateError('Tutorial storage failed.');
    }
  }
}

/// Drives the three-step first-success tutorial (#176).
class TutorialController extends ChangeNotifier {
  TutorialController({this.prefsOverride, TutorialDoneStore? store})
    : _store = store ?? _PreferenceDoneStore(prefsOverride);

  final TutorialDoneStore _store;
  Future<void> _io = Future<void>.value();
  Future<void>? _completion;
  int _generation = 0;
  bool _disposed = false, _resetting = false;
  String? _storageError;

  /// Safe current-run storage failure; null after a successful explicit retry.
  String? get storageError => _storageError;

  /// Current completion future for callers/tests; null when no finish is pending.
  Future<void>? get completion => _completion;

  bool _current(int gen) => !_disposed && gen == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _ordered(Future<void> Function() action) {
    final next = _io.then((_) => action());
    _io = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  /// The app-wide instance shared by the home screen and Settings (replay).
  static final TutorialController instance = TutorialController();

  /// Test seam: an injected store wins over the platform default.
  final SharedPreferences? prefsOverride;

  static const _kDone = 'tutorial.done';

  TutorialStep _step = TutorialStep.wake;
  String _askPrompt = "what's this?";
  bool _pointing = true;

  /// Fits the tutorial to what actually works (#226): the question to ask
  /// and whether the pointing step is offered at all. Without pointing
  /// access the tutorial ends after the first answer, with no success
  /// promised for an action that cannot happen.
  void configure({String? askPrompt, bool pointing = true}) {
    if (askPrompt != null) _askPrompt = askPrompt;
    _pointing = pointing;
    _notify();
  }

  /// The steps this run offers.
  List<TutorialStep> get steps => [
    TutorialStep.wake,
    TutorialStep.ask,
    if (_pointing) TutorialStep.point,
  ];

  /// The current step.
  TutorialStep get step => _step;

  bool _finished = false;

  /// Hides the card without persisting anything: used at startup when the
  /// persisted flag says the tutorial already ran. [reset] undoes it.
  void dismiss() {
    if (_disposed) return;
    ++_generation;
    _completion = null;
    _resetting = false;
    _finished = true;
    _notify();
  }

  /// True once the tutorial completed or was skipped, persisted across
  /// True once the tutorial completed or was skipped, persisted across
  /// restarts. Checked before showing it again.
  static Future<bool> isDone([SharedPreferences? prefs]) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    return store.getBool(_kDone) ?? false;
  }

  /// Skipping at any step finishes the tutorial; failed storage leaves it
  /// visible and throws a safe error. Repeat calls share one current attempt.
  Future<void> skip() => _finish();

  /// Replay invalidates old completion now, then orders removal behind entered
  /// writes. A failed removal keeps prior state and reports a safe failure.
  Future<void> reset() {
    if (_disposed) return Future<void>.value();
    final gen = ++_generation;
    _completion = null;
    _resetting = true;
    return _ordered(() async {
      if (!_current(gen)) return;
      try {
        await _store.clear();
        if (!_current(gen)) return;
        _step = TutorialStep.wake;
        _finished = false;
        _storageError = null;
      } catch (_) {
        if (!_current(gen)) return;
        _storageError = 'Tutorial storage failed.';
        throw StateError(_storageError!);
      } finally {
        if (_current(gen)) {
          _resetting = false;
          _notify();
        }
      }
    });
  }

  /// Whether the tutorial card should render.
  bool get visible => !_finished;

  /// The real wake event (double tap, tray, deep link).
  void notifyAwake() {
    if (_disposed || _resetting || _finished || _step != TutorialStep.wake) {
      return;
    }
    _step = TutorialStep.ask;
    _notify();
  }

  /// A completed ask: the answer bubble arrived.
  void notifyAnswer() {
    if (_disposed || _resetting || _finished || _step != TutorialStep.ask) {
      return;
    }
    if (!_pointing) {
      _finishFromEvent();
      return;
    }
    _step = TutorialStep.point;
    _notify();
  }

  /// A real point_at / point_at_spot execution (#176's "watch him point").
  void notifyPointed() {
    if (_disposed ||
        _resetting ||
        _finished ||
        _step != TutorialStep.point ||
        !_pointing) {
      return;
    }
    _finishFromEvent();
  }

  void _finishFromEvent() {
    // Void event APIs consume failure; storageError is the truthful status.
    unawaited(_finish().catchError((Object _) {}));
  }

  Future<void> _finish() {
    if (_disposed || _resetting || _finished) return Future<void>.value();
    if (_completion != null) return _completion!;
    final gen = _generation;
    final done = Completer<void>();
    _completion = done.future;
    // The internal handler prevents an ignored void-event future escaping.
    unawaited(done.future.catchError((Object _) {}));
    unawaited(
      _ordered(() async {
        if (!_current(gen)) return;
        await _store.markDone();
      }).then(
        (_) {
          if (_current(gen)) {
            _finished = true;
            _storageError = null;
            _notify();
          }
          done.complete();
        },
        onError: (Object _, StackTrace st) {
          if (_current(gen)) {
            _completion = null;
            _storageError = 'Tutorial storage failed.';
            _notify();
            done.completeError(StateError(_storageError!), st);
          } else {
            done.complete();
          }
        },
      ),
    );
    return done.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    super.dispose();
  }

  /// Instruction for the current step.
  String get instruction => switch (_step) {
    TutorialStep.wake => 'Double-tap Bluey\'s face to wake him.',
    TutorialStep.ask => 'Press and hold, ask "$_askPrompt", then let go.',
    TutorialStep.point =>
      'Now ask him to point at something - watch the cursor fly.',
  };
}
