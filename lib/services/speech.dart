import 'request_interfaces.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import 'egress_monitor.dart';
import 'endpoint.dart';
import 'privacy_guard.dart';

import 'package:path_provider/path_provider.dart';

import 'settings_store.dart';

/// Turns the brain's spoken reply into audio: POST {baseUrl}/audio/speech
/// (OpenAI-compatible TTS) and plays the result on the Mac.
class SpeechService implements SpeechLike {
  SpeechService({http.Client? client, AudioPlayer? player})
    : _client = client ?? http.Client(),
      _injectedPlayer = player;

  final http.Client _client;

  /// Injected in tests; created lazily otherwise so synthesize-only paths
  /// never touch the platform audio channel.
  final AudioPlayer? _injectedPlayer;
  AudioPlayer? _lazyPlayer;

  /// Network cap so a stalled TTS server cannot hang a reply (#118).
  static const requestTimeout = Duration(seconds: 60);

  File? _lastTempFile;

  /// Requests speech audio for [text]. Returns the raw audio bytes (mp3).
  @override
  Future<List<int>> synthesize(String text, BrainSettings settings) async {
    final base = settings.ttsBaseUrl?.isNotEmpty == true
        ? settings.ttsBaseUrl!
        : settings.baseUrl;
    // Local-only mode gates TTS exactly like the brain (#120).
    final refusal = await PrivacyGuard.refusalForUrl(base);
    if (refusal != null) throw SpeechException(refusal);
    final headers = {'Content-Type': 'application/json'};
    if (settings.apiKey?.isNotEmpty == true) {
      headers['Authorization'] = 'Bearer ${settings.apiKey}';
    }
    unawaited(EgressMonitor.instance.record(base, 'tts', text.length));
    final response = await _client
        .post(
          Uri.parse(endpoint(base, '/audio/speech')),
          headers: headers,
          body: jsonEncode({
            'model': settings.ttsModel,
            'voice': settings.ttsVoice,
            'input': text,
            'response_format': 'mp3',
          }),
        )
        .timeout(requestTimeout);
    if (response.statusCode != 200) {
      throw SpeechException('Speech ${response.statusCode}: ${response.body}');
    }
    // Checked parsing: some servers return a JSON error with a 200 (#118).
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw SpeechException('Speech returned empty audio');
    }
    if (bytes[0] == 0x7B) {
      // '{' - looks like JSON, not mp3 frames.
      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map) {
          throw SpeechException('Speech returned an error: $decoded');
        }
      } on FormatException {
        // Not valid JSON; treat as audio and let the player judge.
      }
    }
    return bytes;
  }

  /// Plays already-synthesized bytes; pairs with [synthesize] so each answer
  /// costs exactly one TTS request.
  @override
  Future<void> playBytes(List<int> bytes) async {
    // Clean up the previous clip: playback can be interrupted by stop() or
    // a new reply before onPlayerComplete fires, leaking the file (#118).
    await _deleteLastTempFile();
    final file = File(
      '${(await getTemporaryDirectory()).path}/bluey_speech_'
      '${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await file.writeAsBytes(bytes, flush: true);
    _lastTempFile = file;
    final player = _injectedPlayer ?? (_lazyPlayer ??= AudioPlayer());
    await player.play(DeviceFileSource(file.path));
    // Best-effort temp cleanup once playback finishes.
    unawaited(
      player.onPlayerComplete.first.then((_) async {
        if (_lastTempFile?.path == file.path) _lastTempFile = null;
        try {
          await file.delete();
        } catch (_) {}
      }),
    );
  }

  /// Stops any in-flight playback (#91 tray mute).
  Future<void> stop() async {
    await _injectedPlayer?.stop();
    await _lazyPlayer?.stop();
    await _deleteLastTempFile();
  }

  Future<void> _deleteLastTempFile() async {
    final file = _lastTempFile;
    _lastTempFile = null;
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Releases the audio player. Call when the app shuts down.
  Future<void> dispose() async {
    await _injectedPlayer?.dispose();
    await _lazyPlayer?.dispose();
  }
}

/// A speech-pipeline failure (transcription or TTS).
class SpeechException implements Exception {
  SpeechException(this.message);

  /// Human-readable failure detail.
  final String message;
  @override
  String toString() => message;
}
