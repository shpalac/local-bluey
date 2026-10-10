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

  /// Stable preset identifier ('ollama', ...).
  final String id;

  /// Display name in the picker.
  final String label;

  /// The brain backend this preset configures.
  final BrainBackend backend;

  /// Pre-filled endpoint URL.
  final String baseUrl;

  /// Suggested model name for the setup flow.
  final String modelHint;

  /// Whether the endpoint needs an API key.
  final bool requiresKey;

  /// True for on-device endpoints (no cloud egress).
  final bool isLocal;
}

/// The shipped provider presets offered in first-run setup (#175).
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

/// The endpoint answered a real model-list request.
class EndpointCheckOk extends EndpointCheckResult {
  const EndpointCheckOk({required this.latency, required this.models});

  /// Round-trip time of the verification request.
  final Duration latency;

  /// Model ids the endpoint listed; empty when it listed none. Assistant
  /// results are detached read-only lists, not inference readiness proof.
  final List<String> models;
}

/// Why a verification request failed.
enum EndpointCheckFailure { invalidUrl, unreachable, httpError, badResponse }

/// The endpoint could not be verified, with a machine-readable reason.
class EndpointCheckFailed extends EndpointCheckResult {
  const EndpointCheckFailed(this.reason, {this.detail, this.statusCode});

  /// The failure category.
  final EndpointCheckFailure reason;

  /// Optional safe generic failure description, never raw response/error text.
  final String? detail;

  /// HTTP status when the failure was [EndpointCheckFailure.httpError].
  final int? statusCode;
}

/// A local Ollama found by probing its default port.
class OllamaDetection {
  const OllamaDetection({required this.baseUrl, required this.models});

  /// The base URL the local Ollama answered on.
  final String baseUrl;

  /// Model ids it listed; empty when none are pulled yet. Assistant results
  /// are detached read-only lists.
  final List<String> models;

  /// The model the assistant pre-selects: the first one Ollama lists.
  String? get suggestedModel => models.isEmpty ? null : models.first;
}

/// Probes, presets and verification for first-run endpoint setup (#175).
class EndpointAssistant {
  EndpointAssistant({http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 4);

  /// Ollama's default local endpoint.
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
        models: List<String>.unmodifiable(models),
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
    } catch (_) {
      return const EndpointCheckFailed(
        EndpointCheckFailure.unreachable,
        detail: 'Endpoint request failed.',
      );
    }
    sw.stop();
    if (response.statusCode != 200) {
      return EndpointCheckFailed(
        EndpointCheckFailure.httpError,
        statusCode: response.statusCode,
        detail: 'Endpoint returned an HTTP error.',
      );
    }
    try {
      final body = jsonDecode(response.body);
      if (body is! Map) throw const FormatException();
      final raw = body[backend == BrainBackend.ollama ? 'models' : 'data'];
      if (raw is! List) throw const FormatException();
      final idKey = backend == BrainBackend.ollama ? 'name' : 'id';
      final models = <String>[];
      for (final row in raw) {
        if (row is! Map) throw const FormatException();
        final id = row[idKey];
        if (id is! String || id.trim().isEmpty) {
          throw const FormatException();
        }
        models.add(id);
      }
      return EndpointCheckOk(
        latency: sw.elapsed,
        models: List<String>.unmodifiable(models),
      );
    } catch (_) {
      return const EndpointCheckFailed(
        EndpointCheckFailure.badResponse,
        detail: 'Invalid model-list response.',
      );
    }
  }
}
