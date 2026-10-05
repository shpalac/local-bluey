import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_capture.dart';
import 'privacy_guard.dart';
import 'request_interfaces.dart';
import 'stt.dart';

/// Pluggable keyword spotter. A native on-device engine (e.g. Porcupine or a
/// CoreML keyword model) implements this and scores raw audio windows
/// locally. No engine is bundled yet; the service stays dormant without one.
abstract class WakeWordSpotter {
  /// 0..1 confidence that the window contains the wake phrase.
  Future<double> score(File audioWindow);
}

/// Opt-in always-listening wake word (#64). Records short overlapping
/// windows, asks the spotter for a local confidence score, and only then
/// confirms the phrase via the configured transcription endpoint - which
/// must be local when local-only mode is on. The mic indicator is the
/// existing listening status chip; [listening] exposes the state.
class WakeWordService {
  WakeWordService({
    this.spotter,
    AudioCapture? capture,
    TranscriberLike? transcription,
    this.wakePhrase = 'hey bluey',
  }) : _capture = capture ?? AudioCapture(),
       _transcription = transcription;

  static const _kEnabled = 'wake_word.enabled';
  static const windowDuration = Duration(seconds: 2);
  static const scoreThreshold = 0.6;

  final WakeWordSpotter? spotter;
  final AudioCapture _capture;

  /// Injected transcriber (tests); when null the provider is resolved from
  /// the saved STT settings per window, like the request runner (#196).
  final TranscriberLike? _transcription;
  final String wakePhrase;

  final ValueNotifier<bool> listening = ValueNotifier(false);
  bool _running = false;

  /// Called when the wake phrase is confirmed - main wires this to the same
  /// path as hold-to-talk.
  void Function()? onWake;

  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;

  static Future<void> setEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_kEnabled, value);

  Future<void> start() async {
    if (_running) return;
    if (!await isEnabled()) return;
    if (!await _capture.hasPermission()) return;
    _running = true;
    listening.value = true;
    unawaited(_loop());
  }

  Future<void> stop() async {
    _running = false;
    listening.value = false;
  }

  Future<void> _loop() async {
    while (_running) {
      await _capture.start();
      await Future<void>.delayed(windowDuration);
      final file = await _capture.stop();
      if (file == null || !_running) continue;
      try {
        await _scoreAndMaybeWake(file);
      } finally {
        if (file.existsSync()) file.deleteSync();
      }
    }
  }

  @visibleForTesting
  Future<bool> scoreAndMaybeWake(File file) => _scoreAndMaybeWake(file);

  Future<bool> _scoreAndMaybeWake(File file) async {
    final engine = spotter;
    if (engine == null) return false; // no engine bundled; stay dormant
    if (await engine.score(file) < scoreThreshold) return false;

    final stt = await SttSettings.load();
    if (await PrivacyGuard.isLocalOnly()) {
      final endpoint = stt.baseUrl;
      if (endpoint == null || !PrivacyGuard.isLocalUrl(endpoint)) {
        return false; // confirmation would leave the Mac
      }
    }
    final text = await (_transcription ?? SttProviders.create(stt)).transcribe(
      file,
      stt,
    );
    if (!text.toLowerCase().contains(wakePhrase)) return false;
    onWake?.call();
    return true;
  }
}
