import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First-success tutorial (#176): three real interactions right after
/// onboarding - wake Bluey, ask him something, watch him point. Each step
/// completes only on the real event (not on a button press), every step
/// can be skipped, and the whole thing replays from Settings.
enum TutorialStep { wake, ask, point }

/// Drives the three-step first-success tutorial (#176).
class TutorialController extends ChangeNotifier {
  TutorialController({this.prefsOverride});

  /// The app-wide instance shared by the home screen and Settings (replay).
  static final TutorialController instance = TutorialController();

  /// Test seam: an injected store wins over the platform default.
  final SharedPreferences? prefsOverride;

  static const _kDone = 'tutorial.done';

  TutorialStep _step = TutorialStep.wake;

  /// The current step.
  TutorialStep get step => _step;

  bool _finished = false;

  /// Hides the card without persisting anything: used at startup when the
  /// persisted flag says the tutorial already ran. [reset] undoes it.
  void dismiss() {
    _finished = true;
    notifyListeners();
  }

  /// True once the tutorial completed or was skipped, persisted across
  /// True once the tutorial completed or was skipped, persisted across
  /// restarts. Checked before showing it again.
  static Future<bool> isDone([SharedPreferences? prefs]) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    return store.getBool(_kDone) ?? false;
  }

  Future<void> _markDone() async {
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    await prefs.setBool(_kDone, true);
  }

  /// Skipping at any step finishes the tutorial (#176): it must never
  /// block a returning user.
  Future<void> skip() async {
    await _markDone();
    _finished = true;
    notifyListeners();
  }

  /// Settings > Help replay: clears the flag and starts over.
  Future<void> reset() async {
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    await prefs.remove(_kDone);
    _step = TutorialStep.wake;
    _finished = false;
    notifyListeners();
  }

  /// Whether the tutorial card should render.
  bool get visible => !_finished;

  /// The real wake event (double tap, tray, deep link).
  void notifyAwake() {
    if (_finished || _step != TutorialStep.wake) return;
    _step = TutorialStep.ask;
    notifyListeners();
  }

  /// A completed ask: the answer bubble arrived.
  void notifyAnswer() {
    if (_finished || _step != TutorialStep.ask) return;
    _step = TutorialStep.point;
    notifyListeners();
  }

  /// A real point_at / point_at_spot execution (#176's "watch him point").
  void notifyPointed() {
    if (_finished || _step != TutorialStep.point) return;
    _finish();
  }

  Future<void> _finish() async {
    await _markDone();
    _finished = true;
    notifyListeners();
  }

  /// Instruction for the current step.
  String get instruction => switch (_step) {
    TutorialStep.wake => 'Double-tap Bluey\'s face to wake him.',
    TutorialStep.ask => 'Press and hold, ask "what\'s this?", then let go.',
    TutorialStep.point =>
      'Now ask him to point at something - watch the cursor fly.',
  };
}
