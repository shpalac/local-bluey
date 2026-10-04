import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import 'egress_monitor.dart';

import 'package:path_provider/path_provider.dart';

import 'settings_store.dart';

/// Turns the brain's spoken reply into audio: POST {baseUrl}/audio/speech
/// (OpenAI-compatible TTS) and plays the result on the Mac.
class SpeechService {
  SpeechService({http.Client? client, AudioPlayer? player})
    : _client = client ?? http.Client(),
      _injectedPlayer = player;

  final http.Client _client;

  /// Injected in tests; created lazily otherwise so synthesize-only paths
  /// never touch the platform audio channel.
  final AudioPlayer? _injectedPlayer;
  AudioPlayer? _lazyPlayer;

  /// Requests speech audio for [text]. Returns the raw audio bytes (mp3).
  Future<List<int>> synthesize(String text, BrainSettings settings) async {
    final base = settings.ttsBaseUrl?.isNotEmpty == true
        ? settings.ttsBaseUrl!
        : settings.baseUrl;
    final headers = {'Content-Type': 'application/json'};
    if (settings.apiKey?.isNotEmpty == true) {
      headers['Authorization'] = 'Bearer ${settings.apiKey}';
    }
    unawaited(EgressMonitor.instance.record(base, 'tts', text.length));
    final response = await _client.post(
      Uri.parse('$base/audio/speech'),
      headers: headers,
      body: jsonEncode({
        'model': settings.ttsModel,
        'voice': settings.ttsVoice,
        'input': text,
        'response_format': 'mp3',
      }),
    );
    if (response.statusCode != 200) {
      throw SpeechException('Speech ${response.statusCode}: ${response.body}');
    }
    return response.bodyBytes;
  }

  /// Plays already-synthesized bytes; pairs with [synthesize] so each answer
  /// costs exactly one TTS request.
  Future<void> playBytes(List<int> bytes) async {
    final file = File(
      '${(await getTemporaryDirectory()).path}/bluey_speech_'
      '${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await file.writeAsBytes(bytes, flush: true);
    final player = _injectedPlayer ?? (_lazyPlayer ??= AudioPlayer());
    await player.play(DeviceFileSource(file.path));
    // Best-effort temp cleanup once playback finishes.
    unawaited(
      player.onPlayerComplete.first.then((_) async {
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
  }

  /// Releases the audio player. Call when the app shuts down.
  Future<void> dispose() async {
    await _injectedPlayer?.dispose();
    await _lazyPlayer?.dispose();
  }
}

class SpeechException implements Exception {
  SpeechException(this.message);
  final String message;
  @override
  String toString() => message;
}
