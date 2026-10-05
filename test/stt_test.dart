import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/request_interfaces.dart';
import 'package:local_bluey/services/request_runner.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/stt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  const settings = SttSettings(
    baseUrl: 'http://stt.local/v1',
    model: 'whisper-1',
    apiKey: 'sk-stt',
  );

  Future<File> tempFile(String name) =>
      File('${Directory.systemTemp.path}/$name').create();

  test('posts the file and returns the transcript text', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/audio/transcriptions');
      expect(request.headers['authorization'], 'Bearer sk-stt');
      return http.Response(jsonEncode({'text': 'hello bluey'}), 200);
    });
    final text = await HttpSttProvider(client: client)
        .transcribe(await tempFile('s1.m4a'), settings);
    expect(text, 'hello bluey');
  });

  test('trailing slash in base URL does not produce // (#118)', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/audio/transcriptions');
      return http.Response(jsonEncode({'text': 'ok'}), 200);
    });
    final text = await HttpSttProvider(client: client).transcribe(
      await tempFile('s2.m4a'),
      const SttSettings(baseUrl: 'http://stt.local/v1/'),
    );
    expect(text, 'ok');
  });

  test('no endpoint configured fails with modelUnavailable (#196)', () async {
    final client = MockClient((_) async => throw StateError('must not send'));
    final file = await tempFile('s3.m4a');
    expect(
      () =>
          HttpSttProvider(client: client).transcribe(file, const SttSettings()),
      throwsA(
        isA<SttException>().having(
          (e) => e.kind,
          'kind',
          SttErrorKind.modelUnavailable,
        ),
      ),
    );
  });

  test('non-200 raises httpError with the status', () async {
    final client = MockClient((_) async => http.Response('nope', 500));
    final file = await tempFile('s4.m4a');
    expect(
      () => HttpSttProvider(client: client).transcribe(file, settings),
      throwsA(
        isA<SttException>().having(
          (e) => e.kind,
          'kind',
          SttErrorKind.httpError,
        ),
      ),
    );
  });

  test('200 with non-JSON body raises decoderError (#118)', () async {
    final client = MockClient((_) async => http.Response('<html>', 200));
    final file = await tempFile('s5.m4a');
    expect(
      () => HttpSttProvider(client: client).transcribe(file, settings),
      throwsA(
        isA<SttException>().having(
          (e) => e.kind,
          'kind',
          SttErrorKind.decoderError,
        ),
      ),
    );
  });

  test('200 without a text field raises decoderError (#118)', () async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode({'result': 'x'}), 200),
    );
    final file = await tempFile('s6.m4a');
    expect(
      () => HttpSttProvider(client: client).transcribe(file, settings),
      throwsA(
        isA<SttException>().having(
          (e) => e.kind,
          'kind',
          SttErrorKind.decoderError,
        ),
      ),
    );
  });

  test('local-only mode refuses a remote STT endpoint (#120)', () async {
    PrivacyGuard.debugLocalOnlyOverride = true;
    final client = MockClient((_) async => throw StateError('must not send'));
    final file = await tempFile('s7.m4a');
    expect(
      () => HttpSttProvider(client: client).transcribe(file, settings),
      throwsA(
        isA<SttException>().having(
          (e) => e.kind,
          'kind',
          SttErrorKind.unreachable,
        ),
      ),
    );
    PrivacyGuard.debugLocalOnlyOverride = null;
  });

  test(
    'speech language is sent as a field when set, omitted on auto',
    () async {
      var sawLanguage = '';
      final client = MockClient((request) async {
        final body = request.body;
        final m = RegExp(r'name="language"\r\n\r\n([^\r]+)').firstMatch(body);
        sawLanguage = m?.group(1) ?? '';
        return http.Response(jsonEncode({'text': 'ok'}), 200);
      });
      Strings.speechLanguage = 'he';
      await HttpSttProvider(client: client)
          .transcribe(await tempFile('s8.m4a'), settings);
      expect(sawLanguage, 'he');

      var sawField = false;
      final client2 = MockClient((request) async {
        sawField = request.body.contains('name="language"');
        return http.Response(jsonEncode({'text': 'ok'}), 200);
      });
      Strings.speechLanguage = 'auto';
      await HttpSttProvider(client: client2)
          .transcribe(await tempFile('s9.m4a'), settings);
      expect(sawField, isFalse);
      Strings.speechLanguage = 'auto';
    },
  );

  test('native whisper stub throws unsupportedPlatform (#196/#197)', () async {
    final file = await tempFile('s10.m4a');
    expect(
      () => const NativeWhisperSttProvider().transcribe(file, settings),
      throwsA(
        isA<SttException>().having(
          (e) => e.kind,
          'kind',
          SttErrorKind.unsupportedPlatform,
        ),
      ),
    );
  });

  test('factory returns the provider matching the kind (#196)', () {
    expect(SttProviders.create(const SttSettings()), isA<HttpSttProvider>());
    expect(
      SttProviders.create(
        const SttSettings(kind: SttProviderKind.nativeWhisper),
      ),
      isA<NativeWhisperSttProvider>(),
    );
  });

  test(
    'load migrates legacy brain transcription keys exactly once (#196)',
    () async {
      SharedPreferences.setMockInitialValues({
        'brain.transcriptionBaseUrl': 'http://legacy.local/v1',
        'brain.transcriptionModel': 'legacy-whisper',
      });
      final loaded = await SttSettings.load();
      expect(loaded.baseUrl, 'http://legacy.local/v1');
      expect(loaded.model, 'legacy-whisper');
      // Existing explicit values win over legacy ones.
      SharedPreferences.setMockInitialValues({
        'brain.transcriptionBaseUrl': 'http://legacy.local/v1',
        'stt.baseUrl': 'http://explicit.local/v1',
      });
      final loaded2 = await SttSettings.load();
      expect(loaded2.baseUrl, 'http://explicit.local/v1');
    },
  );

  test('unknown persisted kind recovers to http (#196)', () async {
    SharedPreferences.setMockInitialValues({
      'stt.migratedFromBrain': true,
      'stt.kind': 'from-the-future',
    });
    final loaded = await SttSettings.load();
    expect(loaded.kind, SttProviderKind.http);
  });

  test('defaults have no endpoint - never a silent fallback (#196)', () {
    expect(SttSettings.defaults.baseUrl, isNull);
    expect(SttSettings.defaults.apiKey, isNull);
  });

  group('RequestRunner provider selection', () {
    test('resolves the provider from the saved settings when not injected',
        () {
      // No injected transcriber: the kind in settings picks the backend, so
      // choosing native in Settings is not silently ignored (#196).
      final runner = RequestRunner();
      expect(
        runner.transcriberFor(const SttSettings()),
        isA<HttpSttProvider>(),
      );
      expect(
        runner.transcriberFor(
          const SttSettings(kind: SttProviderKind.nativeWhisper),
        ),
        isA<NativeWhisperSttProvider>(),
      );
    });

    test('an injected transcriber always wins over the factory (#196)', () {
      final injected = _RecordingTranscriber();
      final runner = RequestRunner(transcriber: injected);
      expect(
        runner.transcriberFor(
          const SttSettings(kind: SttProviderKind.nativeWhisper),
        ),
        same(injected),
      );
    });
  });
}

class _RecordingTranscriber implements TranscriberLike {
  @override
  Future<String> transcribe(File audio, SttSettings settings) async => '';
}
