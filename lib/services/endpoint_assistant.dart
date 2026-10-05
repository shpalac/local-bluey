import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'egress_monitor.dart';
import 'settings_store.dart';

/// First-run endpoint help (#175): detect a local Ollama, offer provider
/// presets, and verify an endpoint with a real model-list request before it
/// is saved - a wrong URL fails here with a specific reason, not later as a
/// chat timeout.
class EndpointPreset {
  const EndpointPreset({
    required this.id,
    required this.label,
    required this.backend,
    required this.baseUrl,
    required this.modelHint,
    required this.requiresKey,
    required this.isLocal,
  });

  final String id;
  final String label;
  final BrainBackend backend;
  final String baseUrl;
  final String modelHint;
  final bool requiresKey;
  final bool isLocal;
}

const endpointPresets = [
  EndpointPreset(
    id: 'ollama',
    label: 'Ollama (local)',
    backend: BrainBackend.ollama,
    baseUrl: 'http://localhost:11434',
    modelHint: 'llama3.2',
    requiresKey: false,
    isLocal: true,
  ),
  EndpointPreset(
    id: 'localai',
    label: 'LocalAI (local)',
    backend: BrainBackend.openAiCompatible,
    baseUrl: 'http://localhost:8080/v1',
    modelHint: 'ggml-gpt4all-j',
    requiresKey: false,
    isLocal: true,
  ),
  EndpointPreset(
    id: 'openrouter',
    label: 'OpenRouter (cloud)',
    backend: BrainBackend.openAiCompatible,
    baseUrl: 'https://openrouter.ai/api/v1',
    modelHint: 'meta-llama/llama-3.2-3b-instruct',
    requiresKey: true,
    isLocal: false,
  ),
];

/// What a connection check learned.
sealed class EndpointCheckResult {
  const EndpointCheckResult();
}

class EndpointCheckOk extends EndpointCheckResult {
  const EndpointCheckOk({required this.latency, required this.models});
  final Duration latency;

  /// Model ids the endpoint listed; empty when it listed none.
  final List<String> models;
}

enum EndpointCheckFailure { invalidUrl, unreachable, httpError, badResponse }

class EndpointCheckFailed extends EndpointCheckResult {
  const EndpointCheckFailed(this.reason, {this.detail, this.statusCode});
  final EndpointCheckFailure reason;
  final String? detail;
  final int? statusCode;
}

/// A local Ollama found by probing its default port.
class OllamaDetection {
  const OllamaDetection({required this.baseUrl, required this.models});
  final String baseUrl;
  final List<String> models;

  /// The model the assistant pre-selects: the first one Ollama lists.
  String? get suggestedModel => models.isEmpty ? null : models.first;
}

class EndpointAssistant {
  EndpointAssistant({http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 4);

  static const ollamaDefaultBaseUrl = 'http://localhost:11434';

  final http.Client _client;
  final Duration _timeout;

  /// Probes the default Ollama port. Returns null when nothing answers -
  /// "not found" is a normal outcome, never an exception.
  Future<OllamaDetection?> detectLocalOllama() async {
    final result = await checkEndpoint(
      baseUrl: ollamaDefaultBaseUrl,
      backend: BrainBackend.ollama,
    );
    return switch (result) {
      EndpointCheckOk(:final models) => OllamaDetection(
        baseUrl: ollamaDefaultBaseUrl,
        models: models,
      ),
      _ => null,
    };
  }

  /// Runs the model-list request for the backend: GET {base}/api/tags for
  /// Ollama, GET {base}/models for OpenAI-compatible endpoints. Measures
  /// latency and reports a typed failure (#175).
  Future<EndpointCheckResult> checkEndpoint({
    required String baseUrl,
    required BrainBackend backend,
    String? apiKey,
  }) async {
    final clean = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final path = backend == BrainBackend.ollama ? '/api/tags' : '/models';
    final uri = Uri.tryParse('$clean$path');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const EndpointCheckFailed(EndpointCheckFailure.invalidUrl);
    }
    final headers = <String, String>{};
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    unawaited(EgressMonitor.instance.record(clean, 'endpoint-check', 0));
    final sw = Stopwatch()..start();
    final http.Response response;
    try {
      response = await _client.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      return const EndpointCheckFailed(
        EndpointCheckFailure.unreachable,
        detail: 'timed out',
      );
    } catch (e) {
      return EndpointCheckFailed(
        EndpointCheckFailure.unreachable,
        detail: e.toString(),
      );
    }
    sw.stop();
    if (response.statusCode != 200) {
      return EndpointCheckFailed(
        EndpointCheckFailure.httpError,
        statusCode: response.statusCode,
        detail: response.body.length > 200
            ? response.body.substring(0, 200)
            : response.body,
      );
    }
    try {
      final body = jsonDecode(response.body);
      final raw = backend == BrainBackend.ollama
          ? (body['models'] as List?) ?? const []
          : (body['data'] as List?) ?? const [];
      final models = [
        for (final m in raw)
          if (backend == BrainBackend.ollama)
            (m as Map)['name'] as String
          else
            (m as Map)['id'] as String,
      ];
      return EndpointCheckOk(latency: sw.elapsed, models: models);
    } catch (_) {
      return const EndpointCheckFailed(EndpointCheckFailure.badResponse);
    }
  }
}
