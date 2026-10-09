import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:local_bluey/services/data_registry.dart';
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
  late Directory documents;
  setUp(() async {
    documents = await Directory.systemTemp.createTemp('egress-delete-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => documents.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await documents.delete(recursive: true);
  });

  SharedPreferences.setMockInitialValues({});

  const settings = SttSettings(
    baseUrl: 'http://stt.local/v1',
    model: 'whisper-1',
    apiKey: 'sk-stt',
  );

  /// Real bytes, because transcribe() rejects an empty or missing capture
  /// before it builds the request (#254).
  Future<File> tempFile(String name) async {
    final file = await File('${Directory.systemTemp.path}/$name').create();
    await file.writeAsBytes(const [0, 1, 2, 3]);
    return file;
  }

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

  test('redirect in local-only mode is refused, not followed (#199)', () async {
    PrivacyGuard.debugLocalOnlyOverride = true;
    // Local base URL passes the initial gate; the redirect tries to escape.
    const localSettings = SttSettings(baseUrl: 'http://localhost:9/v1');
    final client = MockClient(
      (_) async => http.Response(
        '',
        302,
        headers: {'location': 'https://evil.example/v1'},
      ),
    );
    final file = await tempFile('s11.m4a');
    // ignore: avoid_print
    print('DBG override=${PrivacyGuard.debugLocalOnlyOverride}');
    expect(
      () => HttpSttProvider(client: client).transcribe(file, localSettings),
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

  test('redirects are never followed silently (#199)', () async {
    final client = MockClient(
      (_) async => http.Response(
        '',
        302,
        headers: {'location': 'http://stt.local/v1/other'},
      ),
    );
    final file = await tempFile('s12.m4a');
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

  group('deliberate STT reset (#249)', () {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    late Map<String, String> secrets;
    var failDelete = false;

    setUp(() {
      secrets = {'brain.apiKey': 'legacy-secret'};
      failDelete = false;
      SharedPreferences.setMockInitialValues({
        'brain.transcriptionBaseUrl': 'http://legacy.local/v1',
        'brain.transcriptionModel': 'legacy-whisper',
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final key = call.arguments?['key'] as String?;
            switch (call.method) {
              case 'read':
                return secrets[key];
              case 'write':
                secrets[key!] = call.arguments['value'] as String;
              case 'delete':
                if (failDelete) throw PlatformException(code: 'locked');
                secrets.remove(key);
              case 'deleteAll':
                secrets.clear();
            }
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'reset keeps STT empty without changing legacy brain settings',
      () async {
        expect((await SttSettings.load()).apiKey, 'legacy-secret');
        await SttSettings.clearAll();
        for (var i = 0; i < 3; i++) {
          final loaded = await SttSettings.load();
          expect(loaded.baseUrl, isNull);
          expect(loaded.apiKey, isNull);
          expect(loaded.model, SttSettings.defaults.model);
        }
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('brain.transcriptionBaseUrl'),
          'http://legacy.local/v1',
        );
        expect(prefs.getString('brain.transcriptionModel'), 'legacy-whisper');
        expect(secrets['brain.apiKey'], 'legacy-secret');
        var sends = 0;
        final provider = HttpSttProvider(
          client: MockClient((_) async {
            sends++;
            return http.Response('{}', 200);
          }),
        );
        await expectLater(
          provider.transcribe(
            await tempFile('reset.m4a'),
            await SttSettings.load(),
          ),
          throwsA(
            isA<SttException>().having(
              (e) => e.kind,
              'kind',
              SttErrorKind.modelUnavailable,
            ),
          ),
        );
        expect(sends, 0);
        await SttSettings.save(
          const SttSettings(
            baseUrl: 'http://new.local/v1',
            apiKey: 'new-secret',
          ),
        );
        expect((await SttSettings.load()).apiKey, 'new-secret');
        expect((await SttSettings.load()).baseUrl, 'http://new.local/v1');
      },
    );

    test('fresh legacy install migrates its credential only once', () async {
      expect((await SttSettings.load()).apiKey, 'legacy-secret');
      secrets['brain.apiKey'] = 'changed-legacy';
      expect((await SttSettings.load()).apiKey, 'legacy-secret');
    });

    test('secure deletion failure is reported and can be retried', () async {
      await SttSettings.load();
      failDelete = true;
      await expectLater(SttSettings.clearAll(), throwsStateError);
      expect(secrets['stt.apiKey'], 'legacy-secret');
      failDelete = false;
      await SttSettings.clearAll();
      expect((await SttSettings.load()).apiKey, isNull);
      expect((await SttSettings.load()).baseUrl, isNull);
    });

    test(
      'delete-all followed by restart has defaults, no legacy migration',
      () async {
        await SttSettings.load();
        await DataRegistry.deleteAll();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('brain.transcriptionBaseUrl'), isNull);
        expect(secrets, isEmpty);
        for (var i = 0; i < 2; i++) {
          final loaded = await SttSettings.load();
          expect(loaded.baseUrl, isNull);
          expect(loaded.apiKey, isNull);
          expect(loaded.model, SttSettings.defaults.model);
        }
      },
    );
  });

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
    test('resolves the provider from the saved settings when not injected', () {
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

  _egressGuardTests();
}

class _RecordingTranscriber implements TranscriberLike {
  @override
  Future<String> transcribe(File audio, SttSettings settings) async => '';
}

void _egressGuardTests() {
  // A denied microphone still leaves the recorder reporting its target path, so
  // the file may never exist. Handing it to the multipart builder threw a raw
  // PathNotFoundException, which surfaced as a crash instead of a permissions
  // problem the user can act on (#254).
  test('a missing capture fails clearly instead of crashing (#254)', () async {
    final dir = await Directory.systemTemp.createTemp('sttmissing');
    final missing = File('${dir.path}/never-written.m4a');
    expect(await missing.exists(), isFalse);

    final client = MockClient((_) async => http.Response('{"text":"hi"}', 200));
    final stt = HttpSttProvider(client: client);

    await expectLater(
      stt.transcribe(
        missing,
        const SttSettings(baseUrl: 'http://127.0.0.1:9', model: 'whisper-1'),
      ),
      throwsA(
        isA<SttException>().having(
          (e) => e.message,
          'message',
          contains('microphone'),
        ),
      ),
    );
    await dir.delete(recursive: true);
  });

  test('an empty capture fails clearly instead of crashing (#254)', () async {
    final dir = await Directory.systemTemp.createTemp('sttempty');
    final empty = await File('${dir.path}/silent.m4a').create();

    final client = MockClient((_) async => http.Response('{"text":"hi"}', 200));
    final stt = HttpSttProvider(client: client);

    await expectLater(
      stt.transcribe(
        empty,
        const SttSettings(baseUrl: 'http://127.0.0.1:9', model: 'whisper-1'),
      ),
      throwsA(isA<SttException>()),
    );
    await dir.delete(recursive: true);
  });
}
