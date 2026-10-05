
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:local_bluey/services/endpoint_assistant.dart';
import 'package:local_bluey/services/settings_store.dart';

EndpointAssistant _assistant(
  Future<http.Response> Function(http.Request) handler,
) => EndpointAssistant(client: MockClient(handler));

void main() {
  group('checkEndpoint', () {
    test('ollama: parses model names and reports latency', () async {
      final a = _assistant((req) async {
        expect(req.url.path, '/api/tags');
        return http.Response(
          '{"models":[{"name":"llama3.2"},{"name":"qwen3:4b"}]}',
          200,
        );
      });
      final r = await a.checkEndpoint(
        baseUrl: 'http://localhost:11434',
        backend: BrainBackend.ollama,
      );
      expect(r, isA<EndpointCheckOk>());
      final ok = r as EndpointCheckOk;
      expect(ok.models, ['llama3.2', 'qwen3:4b']);
    });

    test('openai-compatible: hits /models with the bearer key', () async {
      final a = _assistant((req) async {
        expect(req.url.path, '/v1/models');
        expect(req.headers['Authorization'], 'Bearer k');
        return http.Response('{"data":[{"id":"m1"}]}', 200);
      });
      final r = await a.checkEndpoint(
        baseUrl: 'http://localhost:8080/v1/',
        backend: BrainBackend.openAiCompatible,
        apiKey: 'k',
      );
      expect(r, isA<EndpointCheckOk>());
      expect((r as EndpointCheckOk).models, ['m1']);
    });

    test('trailing slashes and whitespace do not break the URL', () async {
      final a = _assistant((req) async {
        expect(req.url.toString(), 'http://localhost:11434/api/tags');
        return http.Response('{"models":[]}', 200);
      });
      final r = await a.checkEndpoint(
        baseUrl: '  http://localhost:11434/  ',
        backend: BrainBackend.ollama,
      );
      expect(r, isA<EndpointCheckOk>());
    });

    test('non-200 is a typed http error with the status', () async {
      final a = _assistant((_) async => http.Response('nope', 503));
      final r = await a.checkEndpoint(
        baseUrl: 'http://localhost:11434',
        backend: BrainBackend.ollama,
      );
      expect(r, isA<EndpointCheckFailed>());
      final f = r as EndpointCheckFailed;
      expect(f.reason, EndpointCheckFailure.httpError);
      expect(f.statusCode, 503);
    });

    test('unparseable response body is badResponse', () async {
      final a = _assistant((_) async => http.Response('<html>', 200));
      final r = await a.checkEndpoint(
        baseUrl: 'http://localhost:11434',
        backend: BrainBackend.ollama,
      );
      expect(
        (r as EndpointCheckFailed).reason,
        EndpointCheckFailure.badResponse,
      );
    });

    test('connection failure is unreachable, not an exception', () async {
      final a = _assistant((_) async => throw http.ClientException('refused'));
      final r = await a.checkEndpoint(
        baseUrl: 'http://localhost:9',
        backend: BrainBackend.ollama,
      );
      expect(
        (r as EndpointCheckFailed).reason,
        EndpointCheckFailure.unreachable,
      );
    });

    test('timeout is unreachable with a timed-out detail', () async {
      final a = EndpointAssistant(
        timeout: const Duration(milliseconds: 10),
        client: MockClient(
          (_) => Future.delayed(
            const Duration(seconds: 1),
            () => http.Response('{}', 200),
          ),
        ),
      );
      final r = await a.checkEndpoint(
        baseUrl: 'http://localhost:11434',
        backend: BrainBackend.ollama,
      );
      final f = r as EndpointCheckFailed;
      expect(f.reason, EndpointCheckFailure.unreachable);
      expect(f.detail, 'timed out');
    });

    test('an empty base url is invalidUrl', () async {
      final r = await _assistant((_) async => http.Response('{}', 200))
          .checkEndpoint(baseUrl: '', backend: BrainBackend.ollama);
      expect(
        (r as EndpointCheckFailed).reason,
        EndpointCheckFailure.invalidUrl,
      );
    });
  });

  group('detectLocalOllama', () {
    test('returns the detection with a suggested model', () async {
      final a = _assistant(
        (_) async =>
            http.Response('{"models":[{"name":"llama3.2:latest"}]}', 200),
      );
      final d = await a.detectLocalOllama();
      expect(d, isNotNull);
      expect(d!.baseUrl, EndpointAssistant.ollamaDefaultBaseUrl);
      expect(d.suggestedModel, 'llama3.2:latest');
    });

    test('returns null when nothing answers', () async {
      final a = _assistant((_) async => throw http.ClientException('down'));
      expect(await a.detectLocalOllama(), isNull);
    });
  });

  group('presets', () {
    test('cover Ollama, LocalAI and OpenRouter with the right URL shapes', () {
      expect(endpointPresets.map((p) => p.id), [
        'ollama',
        'localai',
        'openrouter',
      ]);
      final ollama = endpointPresets.firstWhere((p) => p.id == 'ollama');
      expect(ollama.backend, BrainBackend.ollama);
      expect(ollama.baseUrl, 'http://localhost:11434');
      expect(ollama.requiresKey, isFalse);
      final openrouter = endpointPresets.firstWhere(
        (p) => p.id == 'openrouter',
      );
      expect(openrouter.backend, BrainBackend.openAiCompatible);
      expect(openrouter.requiresKey, isTrue);
      expect(openrouter.isLocal, isFalse);
    });
  });
}
