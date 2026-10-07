import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'egress_monitor.dart';
import 'endpoint.dart';
import 'privacy_guard.dart';
import 'request_interfaces.dart';
import 'strings.dart';

/// Speech-to-text provider kinds (#196): explicit HTTP endpoint today,
/// native whisper.cpp once it is installed and benchmark-qualified (#195).
/// Which STT backend is active. [http] posts to an explicit endpoint;
/// [nativeWhisper] is the on-device whisper.cpp worker (#197).
enum SttProviderKind { http, nativeWhisper }

/// STT configuration, deliberately separate from the LLM settings (#196):
/// its own provider, model, language and credentials. Missing config must
/// fail loudly - never silently route audio to Ollama or a cloud service.
class SttSettings {
  const SttSettings({
    this.kind = SttProviderKind.http,
    this.baseUrl,
    this.model = 'whisper-1',
    this.apiKey,
  });

  /// The active backend.
  final SttProviderKind kind;

  /// HTTP endpoint for [SttProviderKind.http]; required there, unused
  /// for native.
  final String? baseUrl;

  /// Model name sent to the endpoint (e.g. 'whisper-1').
  final String model;

  /// Endpoint credential, kept in secure storage.
  final String? apiKey;

  static const _kKind = 'stt.kind';
  static const _kBaseUrl = 'stt.baseUrl';
  static const _kModel = 'stt.model';
  static const _kApiKey = 'stt.apiKey';
  static const _kMigrated = 'stt.migratedFromBrain';

  // Legacy keys that lived under the brain settings before #196.
  static const _kLegacyBaseUrl = 'brain.transcriptionBaseUrl';
  static const _kLegacyModel = 'brain.transcriptionModel';
  static const _kLegacyApiKey = 'brain.apiKey';

  static FlutterSecureStorage _secure = const FlutterSecureStorage();

  /// Test seam, same pattern as BrainSettings.debugSecureStorage (#123).
  static set debugSecureStorage(FlutterSecureStorage? value) {
    _secure = value ?? const FlutterSecureStorage();
  }

  /// The out-of-box configuration (HTTP kind, no endpoint set).
  static const defaults = SttSettings();

  /// Loads STT settings, migrating the legacy brain-era keys once (#196):
  /// the previous behavior (fall back to the brain URL/key) becomes an
  /// explicit copy, so no request ever falls back silently again.
  static Future<SttSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kMigrated) != true) {
      await _migrate(prefs);
    }
    String? apiKey;
    try {
      apiKey = await _secure.read(key: _kApiKey);
    } catch (_) {
      apiKey = null; // locked keychain / tests: treat as no key (#123)
    }
    final kindName = prefs.getString(_kKind);
    return SttSettings(
      kind:
          SttProviderKind.values.asNameMap()[kindName] ??
          SttProviderKind.http, // unknown provider recovers to http
      baseUrl: prefs.getString(_kBaseUrl),
      model: prefs.getString(_kModel) ?? defaults.model,
      apiKey: apiKey,
    );
  }

  static Future<void> _migrate(SharedPreferences prefs) async {
    final legacyUrl = prefs.getString(_kLegacyBaseUrl);
    if (prefs.getString(_kBaseUrl) == null && legacyUrl?.isNotEmpty == true) {
      await prefs.setString(_kBaseUrl, legacyUrl!);
    }
    final legacyModel = prefs.getString(_kLegacyModel);
    if (prefs.getString(_kModel) == null && legacyModel?.isNotEmpty == true) {
      await prefs.setString(_kModel, legacyModel!);
    }
    // The old code reused the brain API key per request. Copy it once into
    // STT's own slot; nothing reads the brain key for STT after this.
    try {
      final legacyKey = await _secure.read(key: _kLegacyApiKey);
      if (legacyKey != null &&
          legacyKey.isNotEmpty &&
          await _secure.read(key: _kApiKey) == null) {
        await _secure.write(key: _kApiKey, value: legacyKey);
      }
    } catch (_) {
      // Secure storage unavailable: skip key migration, keep the rest.
    }
    await prefs.setBool(_kMigrated, true);
  }

  /// Persists [settings]; the API key goes to secure storage, the rest
  /// to SharedPreferences.
  static Future<void> save(SttSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      if (settings.apiKey == null || settings.apiKey!.isEmpty) {
        await _secure.delete(key: _kApiKey);
      } else {
        await _secure.write(key: _kApiKey, value: settings.apiKey!);
      }
    } catch (e) {
      throw StateError('Could not save the STT API key: $e');
    }
    await prefs.setString(_kKind, settings.kind.name);
    if (settings.baseUrl == null || settings.baseUrl!.isEmpty) {
      await prefs.remove(_kBaseUrl);
    } else {
      await prefs.setString(_kBaseUrl, settings.baseUrl!);
    }
    await prefs.setString(_kModel, settings.model);
    await prefs.setBool(_kMigrated, true);
  }

  /// Clears STT configuration and credentials without reviving legacy brain
  /// values on the next load (#249). The migration tombstone contains no
  /// user data; delete-all removes it after also clearing legacy settings.
  /// Throws if the secure credential could not be deleted.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    // Mark the reset before removing values so a later load cannot migrate
    // old credentials back, including when secure deletion needs a retry.
    await prefs.setBool(_kMigrated, true);
    try {
      await _secure.delete(key: _kApiKey);
    } catch (e) {
      throw StateError('Could not delete the STT API key: $e');
    }
    for (final key in [_kKind, _kBaseUrl, _kModel]) {
      await prefs.remove(key);
    }
  }
}

/// Structured STT failures (#196): the UI reacts to the kind, never
/// parses message text.
enum SttErrorKind {
  /// The configured model is not installed / not available server-side.
  modelUnavailable,

  /// The requested language is not supported by the backend.
  unsupportedLanguage,

  /// This backend cannot run on the current platform.
  unsupportedPlatform,

  /// The audio could not be decoded to PCM.
  decoderError,

  /// Another transcription is already running.
  busy,

  /// The request exceeded [HttpSttProvider.requestTimeout].
  timeout,

  /// The user cancelled.
  cancelled,

  /// The endpoint could not be reached at all.
  unreachable,

  /// The endpoint answered with a non-2xx status.
  httpError,
}

/// An STT failure with a machine-readable [kind] for the UI.
class SttException implements Exception {
  SttException(this.kind, this.message);

  /// The failure category.
  final SttErrorKind kind;

  /// User-presentable description.
  final String message;
  @override
  String toString() => message;
}

/// Explicit OpenAI-compatible HTTP transcription (#196): POST
/// {baseUrl}/audio/transcriptions with STT's own model and credentials.
/// Implements the existing TranscriberLike seam, now STT-scoped.
/// Posts audio to the configured HTTP endpoint as multipart and reads
/// back JSON `text`. Honors local-only mode by refusing to send (#199).
class HttpSttProvider implements TranscriberLike {
  HttpSttProvider({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Network cap so a stalled server cannot pin the UI in "thinking" (#118).
  /// Hard ceiling on one transcription request.
  static const requestTimeout = Duration(seconds: 120);

  @override
  /// Transcribes [audio]. Throws [SttException] when no endpoint is
  /// configured, local-only mode blocks egress, or the endpoint fails.
  @override
  Future<String> transcribe(File audio, SttSettings settings) async {
    final base = settings.baseUrl;
    if (base == null || base.isEmpty) {
      throw SttException(
        SttErrorKind.modelUnavailable,
        'No transcription endpoint configured - set one in Settings.',
      );
    }
    // Local-only mode gates audio uploads exactly like the brain (#120).
    // Snapshot the local-only decision once for the whole request (#199):
    // the redirect check below must not re-read mutable global state.
    final localOnly = await PrivacyGuard.isLocalOnly();
    if (localOnly && !PrivacyGuard.isLocalUrl(base)) {
      throw SttException(
        SttErrorKind.unreachable,
        'Local-only mode is on - $base is off-device.',
      );
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(endpoint(base, '/audio/transcriptions')),
    );
    request.fields['model'] = settings.model;
    if (Strings.speechLanguage != 'auto') {
      request.fields['language'] = Strings.speechLanguage;
    }
    // STT credentials only - never the brain key (#196).
    if (settings.apiKey?.isNotEmpty == true) {
      request.headers['Authorization'] = 'Bearer ${settings.apiKey}';
    }
    request.files.add(await http.MultipartFile.fromPath('file', audio.path));
    unawaited(
      EgressMonitor.instance.record(
        base,
        'transcription',
        await audio.length(),
      ),
    );
    final http.Response response;
    try {
      // #199: the deadline covers the body read too, not just send() - a
      // stalled response stream cannot pin the UI in "thinking".
      // Redirects are validated below instead of followed blindly.
      request.followRedirects = false;
      final streamed = await _client.send(request).timeout(requestTimeout);
      response = await http.Response.fromStream(streamed)
          .timeout(requestTimeout);
    } on TimeoutException {
      throw SttException(
        SttErrorKind.timeout,
        'Transcription timed out after ${requestTimeout.inSeconds}s',
      );
    }
    // Some clients normalize redirect state away; check the status and
    // location header directly so a 3xx can never slip through.
    final isRedirect =
        response.statusCode >= 300 &&
        response.statusCode < 400 &&
        response.headers.containsKey('location');
    if (isRedirect) {
      // #199: never follow redirects silently - in local-only mode a
      // redirect to a remote host would leak audio off-device.
      final location = response.headers['location'] ?? '';
      if (localOnly && !PrivacyGuard.isLocalUrl(location)) {
        throw SttException(
          SttErrorKind.unreachable,
          'Local-only mode is on - the transcription endpoint redirected '
          'off-device ($location).',
        );
      }
      throw SttException(
        SttErrorKind.httpError,
        'Transcription endpoint redirects are not followed ($location).',
      );
    }
    if (response.statusCode != 200) {
      throw SttException(
        SttErrorKind.httpError,
        'Transcription ${response.statusCode}: ${response.body}',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw SttException(
        SttErrorKind.decoderError,
        'Transcription returned a non-JSON response',
      );
    }
    if (decoded is! Map || decoded['text'] is! String) {
      throw SttException(
        SttErrorKind.decoderError,
        'Transcription response is missing the "text" field',
      );
    }
    return (decoded['text'] as String).trim();
  }
}

/// Native whisper.cpp placeholder (#196/#197): selected explicitly but not
/// installed yet, so every call fails with a typed error instead of a
/// missing-plugin crash. Enabled as a default only after #195 qualifies it.
/// On-device whisper.cpp worker (#197). Not integrated yet: every call
/// fails loudly with a "not installed" error instead of falling back to
/// a cloud route.
class NativeWhisperSttProvider implements TranscriberLike {
  const NativeWhisperSttProvider();

  @override
  Future<String> transcribe(File audio, SttSettings settings) async {
    throw SttException(
      SttErrorKind.unsupportedPlatform,
      'Native transcription is not installed yet (tracked in #197). '
      'Pick the HTTP provider or type instead.',
    );
  }
}

/// Picks the concrete provider for a settings snapshot (#196).
/// Factory: builds the [TranscriberLike] for the configured kind.
class SttProviders {
  /// Returns the provider for [settings.kind]. [client] is a test seam.
  static TranscriberLike create(SttSettings settings, {http.Client? client}) =>
      switch (settings.kind) {
        SttProviderKind.http => HttpSttProvider(client: client),
        SttProviderKind.nativeWhisper => const NativeWhisperSttProvider(),
      };
}
