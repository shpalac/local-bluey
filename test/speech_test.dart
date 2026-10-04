import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:local_bluey/services/speech.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const settings = BrainSettings(
    backend: BrainBackend.openAiCompatible,
    baseUrl: 'http://brain.local/v1',
    model: 'm',
    apiKey: 'sk-test',
    ttsModel: 'tts-1',
    ttsVoice: 'alloy',
  );

  test('posts model, voice and input; returns audio bytes', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/audio/speech');
      expect(request.headers['authorization'], 'Bearer sk-test');
      expect(request.body, contains('"voice":"alloy"'));
      expect(request.body, contains('"input":"hello"'));
      return http.Response.bytes([1, 2, 3], 200);
    });
    final bytes = await SpeechService(
      client: client,
    ).synthesize('hello', settings);
    expect(bytes, [1, 2, 3]);
  });

  test('dedicated TTS URL wins over the brain base URL', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'tts.local');
      return http.Response.bytes([], 200);
    });
    await SpeechService(client: client).synthesize(
      'hi',
      const BrainSettings(
        backend: BrainBackend.openAiCompatible,
        baseUrl: 'http://brain.local/v1',
        model: 'm',
        ttsBaseUrl: 'http://tts.local/v1',
      ),
    );
  });

  test('non-200 raises SpeechException', () async {
    final client = MockClient((_) async => http.Response('nope', 500));
    expect(
      () => SpeechService(client: client).synthesize('hi', settings),
      throwsA(isA<SpeechException>()),
    );
  });
}
