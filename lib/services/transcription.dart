import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'egress_monitor.dart';

import 'settings_store.dart';
import 'strings.dart';

/// Sends a recorded audio file to an OpenAI-compatible
/// POST {baseUrl}/audio/transcriptions endpoint and returns the text.
/// Falls back to the brain's base URL when no dedicated transcription URL
/// is set, so a single LM Studio / OpenRouter-style endpoint covers both.
class TranscriptionService {
  TranscriptionService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// Takes settings explicitly so callers can cache them and tests can
  /// inject them without touching platform storage.
  Future<String> transcribe(File audio, BrainSettings settings) async {
    final base = settings.transcriptionBaseUrl?.isNotEmpty == true
        ? settings.transcriptionBaseUrl!
        : settings.baseUrl;
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/audio/transcriptions'),
    );
    request.fields['model'] = settings.transcriptionModel;
    if (Strings.speechLanguage != 'auto') {
      request.fields['language'] = Strings.speechLanguage;
    }
    if (settings.apiKey?.isNotEmpty == true) {
      request.headers['Authorization'] = 'Bearer ${settings.apiKey}';
    }
    request.files.add(await http.MultipartFile.fromPath('file', audio.path));
    unawaited(
      EgressMonitor.instance.record(base, 'transcription', await audio.length()),
    );
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw TranscriptionException(
        'Transcription ${response.statusCode}: ${response.body}',
      );
    }
    final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    return (body['text'] as String? ?? '').trim();
  }
}

class TranscriptionException implements Exception {
  TranscriptionException(this.message);
  final String message;
  @override
  String toString() => message;
}
