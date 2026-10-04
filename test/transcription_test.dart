import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:local_bluey/services/transcription.dart';

void main() {
  const settings = BrainSettings(
    backend: BrainBackend.openAiCompatible,
    baseUrl: 'http://brain.local/v1',
    model: 'm',
    apiKey: 'sk-test',
  );

  test('posts the file and returns the transcript text', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/audio/transcriptions');
      expect(request.headers['authorization'], 'Bearer sk-test');
      return http.Response(jsonEncode({'text': 'hello bluey'}), 200);
    });
    final file = await File('${Directory.systemTemp.path}/t.m4a').create();
    final text = await TranscriptionService(
      client: client,
    ).transcribe(file, settings);
    expect(text, 'hello bluey');
  });

  test('dedicated transcription URL wins over the brain base URL', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'whisper.local');
      return http.Response(jsonEncode({'text': 'hi'}), 200);
    });
    final file = await File('${Directory.systemTemp.path}/t2.m4a').create();
    await TranscriptionService(client: client).transcribe(
      file,
      const BrainSettings(
        backend: BrainBackend.openAiCompatible,
        baseUrl: 'http://brain.local/v1',
        model: 'm',
        transcriptionBaseUrl: 'http://whisper.local/v1',
      ),
    );
  });

  test('non-200 raises TranscriptionException', () async {
    final client = MockClient((_) async => http.Response('nope', 500));
    final file = await File('${Directory.systemTemp.path}/t3.m4a').create();
    expect(
      () => TranscriptionService(client: client).transcribe(file, settings),
      throwsA(isA<TranscriptionException>()),
    );
  });
}
