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
/// windows and asks the spotter for a local confidence score. A wake is
/// confirmed by transcription only when that stays on this machine;
/// otherwise the spotter alone decides and no audio is uploaded (#79). The mic indicator is the
/// existing listening status chip; [listening] exposes the state.
class WakeWordService {
  WakeWordService({
    this.spotter,
    AudioCapture? capture,
    TranscriberLike? transcription,
    this.wakePhrase = 'hey bluey',
    Future<void> Function(Duration)? windowDelay,
  }) : _capture = capture ?? AudioCapture(),
       _windowDelay = windowDelay ?? Future<void>.delayed,
       // Private field, public named parameter: no initializing formal.
       // ignore: prefer_initializing_formals
       _transcription = transcription;

  static const _kEnabled = 'wake_word.enabled';

  /// Length of one audio window the spotter scores.
  static const windowDuration = Duration(seconds: 2);

  /// Minimum spotter score that counts as a wake (#79).
  static const scoreThreshold = 0.6;

  /// The on-device spotter; null while #79 is unshipped (service stays
  /// dormant: no recorder is started without an engine).
  final WakeWordSpotter? spotter;
  final AudioCapture _capture;
  final Future<void> Function(Duration) _windowDelay;

  /// Injected transcriber (tests); when null the provider is resolved from
  /// the saved STT settings per window, like the request runner (#196).
  final TranscriberLike? _transcription;

  /// The phrase that wakes Bluey.
  final String wakePhrase;

  /// Whether the service is currently listening; the UI binds to this.
  final ValueNotifier<bool> listening = ValueNotifier(false);

  /// Last failure (permission, recorder, scoring), or null. Cleared by the
  /// next [start]; a failure leaves the service stopped and retryable.
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  bool _running = false;

  /// Bumped by every start and stop. Work from an older generation is
  /// stale: it may clean up its files but never wakes or touches notifiers.
  int _generation = 0;
  Future<void>? _loopFuture;
  Completer<void>? _cancelWindow;

  /// Called when the wake phrase is confirmed - main wires this to the same
  /// path as hold-to-talk.
  void Function()? onWake;

  /// The persisted on/off preference.
  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;

  /// Persists the on/off preference.
  static Future<void> setEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_kEnabled, value);

  /// Starts listening. Does nothing without a spotter engine (#79), when
  /// disabled, or without permission; permission and recorder problems are
  /// reported through [lastError]. A restart waits for the old loop to end,
  /// so at most one loop ever owns the recorder.
  Future<void> start() async {
    if (_running) return;
    final gen = ++_generation;
    lastError.value = null;
    if (spotter == null) return;
    await _loopFuture;
    if (gen != _generation) return;
    try {
      if (!await isEnabled()) return;
      if (gen != _generation) return;
      if (!await _capture.hasPermission()) {
        if (gen == _generation) {
          lastError.value = 'Microphone permission is off';
        }
        return;
      }
    } on Object catch (e) {
      if (gen == _generation) {
        lastError.value = 'Wake word could not start: $e';
      }
      return;
    }
    if (gen != _generation) return;
    _running = true;
    listening.value = true;
    _loopFuture = _loop(gen);
  }

  /// Stops listening: closes an open recording, suppresses any score or
  /// confirmation still in flight, and waits until the loop has ended.
  Future<void> stop() async {
    _generation++;
    _running = false;
    listening.value = false;
    final cancel = _cancelWindow;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    await _loopFuture;
  }

  Future<void> _loop(int gen) async {
    bool current() => _running && gen == _generation;
    try {
      while (current()) {
        // Registered before start so a stop during start cancels the window.
        final cancel = _cancelWindow = Completer<void>();
        await _capture.start();
        Object? windowError;
        StackTrace? windowTrace;
        if (current()) {
          try {
            await Future.any<void>([
              _windowDelay(windowDuration),
              cancel.future,
            ]);
          } on Object catch (e, st) {
            windowError = e;
            windowTrace = st;
          }
        }
        // Whatever happened above, the open recording is closed and its file
        // is owned (scored or deleted) here, including on error paths.
        File? file;
        try {
          file = await _capture.stop();
        } on Object catch (e, st) {
          windowError ??= e;
          windowTrace ??= st;
        }
        try {
          if (windowError == null && file != null && current()) {
            await _scoreAndMaybeWake(file, gen: gen);
          }
        } finally {
          await AudioCapture.deleteQuietly(file);
        }
        if (windowError != null) {
          Error.throwWithStackTrace(windowError, windowTrace!);
        }
      }
    } on Object catch (e) {
      if (gen == _generation) lastError.value = 'Wake word stopped: $e';
    } finally {
      try {
        await AudioCapture.deleteQuietly(await _capture.stop());
      } on Object catch (_) {
        // The recorder is already gone; nothing left to close.
      }
      if (gen == _generation) {
        _running = false;
        listening.value = false;
      }
    }
  }

  @visibleForTesting
  /// Scores one recorded window; true when it triggered a wake.
  Future<bool> scoreAndMaybeWake(File file) => _scoreAndMaybeWake(file);

  Future<bool> _scoreAndMaybeWake(File file, {int? gen}) async {
    final engine = spotter;
    if (engine == null) return false; // no engine bundled; stay dormant
    bool stale() => gen != null && (gen != _generation || !_running);
    if (await engine.score(file) < scoreThreshold || stale()) return false;

    // The spotter already fired on-device. Confirm via transcription only
    // when that stays on this machine (an injected transcriber, or a local
    // endpoint); otherwise trust the spotter and never upload the audio.
    final stt = await SttSettings.load();
    final endpoint = stt.baseUrl;
    final canConfirmLocally =
        _transcription != null ||
        (endpoint != null && PrivacyGuard.isLocalUrl(endpoint));
    if (canConfirmLocally) {
      final text = await (_transcription ?? SttProviders.create(stt))
          .transcribe(file, stt);
      if (stale() || !text.toLowerCase().contains(wakePhrase)) return false;
    }
    if (stale()) return false;
    onWake?.call();
    return true;
  }
}
