import 'package:flutter/foundation.dart';

import '../services/capture_monitor.dart';
import '../services/screen_watch.dart';
import 'draft_builder.dart';

/// Explicit-consent, memory-only Teach Mode lifecycle.
class TeachCaptureSession extends ChangeNotifier {
  TeachCaptureSession({required ScreenWatch watch})
    : _watch = watch,
      _monitor = CaptureMonitor(watch: watch) {
    _monitor.addListener(_onChanged);
  }

  final ScreenWatch _watch;
  final CaptureMonitor _monitor;
  final List<Map<String, Object?>> _steps = [];
  final TeachDraftBuilder _builder = const TeachDraftBuilder();
  int _epoch = 0;
  bool _disposed = false;

  CaptureIndicator get indicator =>
      _disposed ? CaptureIndicator.off : _monitor.indicator;
  int get stepCount => _steps.length;

  Future<String?> start({
    required bool consentConfirmed,
    Duration duration = const Duration(minutes: 10),
  }) async {
    if (_disposed) return 'Teach Mode is disposed.';
    if (!consentConfirmed) return 'Explicit user consent is required.';
    if (duration <= Duration.zero || duration > const Duration(minutes: 10)) {
      return 'Duration must be positive and at most ten minutes.';
    }
    if (_watch.isActive) return 'A session is already active.';
    _discard();
    return _watch.start(length: duration, consentConfirmed: true);
  }

  void _discard() {
    _epoch++;
    _steps.clear();
  }

  void _onChanged() {
    if (_monitor.indicator != CaptureIndicator.active) {
      _discard();
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  bool pause() => _monitor.pause();
  bool resume() => _monitor.resume();

  void cancel() {
    _discard();
    _monitor.stop();
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Only validated, payload-free step identifiers pass the capture gate.
  Future<bool> observe({
    required String frontApp,
    String? windowTitle,
    bool locked = false,
    required Future<Map<String, Object?>> Function() capture,
  }) async {
    if (_disposed || indicator != CaptureIndicator.active) return false;
    final epoch = _epoch;
    final result = await _monitor.runIfAllowed<Map<String, Object?>>(
      frontApp: frontApp,
      windowTitle: windowTitle,
      locked: locked,
      operation: capture,
    );
    if (_disposed ||
        epoch != _epoch ||
        indicator != CaptureIndicator.active ||
        result == null) {
      return false;
    }
    final step = _builder.build([result]).steps.single;
    if (step.uncertain) {
      return false;
    }
    _steps.add({'action': result['action'], 'target': step.target});
    notifyListeners();
    return true;
  }

  TeachDraft finish() {
    final draft = _builder.build(_steps);
    cancel();
    return draft;
  }

  @override
  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
    _monitor.removeListener(_onChanged);
    _monitor.dispose();
    super.dispose();
  }
}
