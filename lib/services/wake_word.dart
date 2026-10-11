import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_capture.dart';
import 'privacy_guard.dart';
import 'request_interfaces.dart';
import 'stt.dart';

/// Pluggable window scorer intended for an on-device engine; none is bundled.
/// Injected implementation internals are not verified as local by this interface.
/// The service stays dormant without a spotter.
abstract class WakeWordSpotter {
  /// 0..1 confidence that the window contains the wake phrase.
  Future<double> score(File audioWindow);
}

/// Dormant opt-in wake scaffold (#64/#79), default off with no bundled engine.
/// Windows run serial capture/start, delay, stop, score and optional confirmation,
/// not overlapping PCM. No production app construction, callback, Settings or
/// listening/error binding is wired. Manual face wake is a separate path.
/// Positive scores use an injected transcriber or loopback-configured STT for
/// confirmation; otherwise this service skips transcription and trusts the score.
/// This branch is not a no-upload guarantee for injected engines/transcribers.
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

  /// Logical listening state; no current production UI binding.
  /// False at stop entry does not confirm physical capture cleanup.
  final ValueNotifier<bool> listening = ValueNotifier(false);

  /// Current start/loop failure, cleared by the next [start]. No app binding.
  /// Raw interpolated errors and suppressed cleanup failures are current behavior,
  /// not a safe notice or verified stopped-hardware contract.
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  bool _running = false;

  /// Bumped by every start and stop. Work from an older generation is
  /// stale: it may clean up its files but never wakes or touches notifiers.
  int _generation = 0;
  Future<void>? _loopFuture;

  /// Test seam: runs right after the STT settings load, before the
  /// generation is re-checked and the transcriber is invoked.
  @visibleForTesting
  Future<void> Function()? debugAfterSettingsLoad;
  Completer<void>? _cancelWindow;

  /// Optional scored/confirmed wake callback. Main does not register it today;
  /// this is not the manual face onWakeChanged callback.
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

  /// Invalidates the generation, cancels the window delay and joins the loop.
  /// Late score/confirmation cannot wake; entered start/score/STT may still run
  /// and hold this join. Cleanup is attempted, not physical stop/erasure proof.
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
        // Attempt capture stop even on a window error. A thrown stop can retain
        // capture ownership; a returned file is scored/deletion-attempted below.
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
        // Suppress final stop failure; retained cleanup may still be unresolved.
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

    // Positive score: injected transcription is trusted, not verified local.
    // Otherwise loopback URL spelling allows confirmation without a DNS probe;
    // remote/missing endpoints skip this service's STT call. This does not audit
    // engine/transcriber internals or qualify native/provider readiness.
    final stt = await SttSettings.load();
    await debugAfterSettingsLoad?.call();
    if (stale()) return false;
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
