import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
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
      throw SpeechException(
        'Speech ${response.statusCode}: ${response.body}',
      );
    }
    return response.bodyBytes;
  }

  /// Synthesizes and plays the reply out loud.
  Future<void> speak(String text, BrainSettings settings) async {
    final bytes = await synthesize(text, settings);
    final file = File(
      '${(await getTemporaryDirectory()).path}/bluey_speech_'
      '${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await file.writeAsBytes(bytes, flush: true);
    final player = _injectedPlayer ?? (_lazyPlayer ??= AudioPlayer());
    await player.play(DeviceFileSource(file.path));
  }
}

class SpeechException implements Exception {
  SpeechException(this.message);
  final String message;
  @override
  String toString() => message;
}
