import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/brain.dart';
import '../llm/llm_provider.dart';
import '../llm/ollama_provider.dart';
import '../llm/openai_compatible_provider.dart';

import 'characters.dart';

enum BrainBackend { ollama, openAiCompatible }

/// The user's LLM connection choices. Non-secret fields live in
/// SharedPreferences; the API key lives in the Keychain (iOS/macOS) via
/// flutter_secure_storage and is never written to plain storage.
class BrainSettings {
  const BrainSettings({
    required this.backend,
    required this.baseUrl,
    required this.model,
    this.apiKey,
    this.transcriptionBaseUrl,
    this.transcriptionModel = 'whisper-1',
    this.ttsBaseUrl,
    this.ttsModel = 'tts-1',
    this.ttsVoice = 'alloy',
  });

  final BrainBackend backend;
  final String baseUrl;
  final String model;
  final String? apiKey;

  /// Optional dedicated /audio/transcriptions endpoint; defaults to baseUrl.
  final String? transcriptionBaseUrl;
  final String transcriptionModel;

  /// Optional dedicated /audio/speech endpoint; defaults to baseUrl.
  final String? ttsBaseUrl;
  final String ttsModel;
  final String ttsVoice;

  static const defaults = BrainSettings(
    backend: BrainBackend.ollama,
    baseUrl: 'http://localhost:11434',
    model: 'llama3.2',
  );

  BrainSettings copyWith({
    BrainBackend? backend,
    String? baseUrl,
    String? model,
    String? apiKey,
    String? transcriptionBaseUrl,
    String? transcriptionModel,
    String? ttsBaseUrl,
    String? ttsModel,
    String? ttsVoice,
  }) => BrainSettings(
    backend: backend ?? this.backend,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
    transcriptionBaseUrl: transcriptionBaseUrl ?? this.transcriptionBaseUrl,
    transcriptionModel: transcriptionModel ?? this.transcriptionModel,
    ttsBaseUrl: ttsBaseUrl ?? this.ttsBaseUrl,
    ttsModel: ttsModel ?? this.ttsModel,
    ttsVoice: ttsVoice ?? this.ttsVoice,
  );

  LlmProvider buildProvider() => switch (backend) {
    BrainBackend.ollama => OllamaProvider(baseUrl: baseUrl, model: model),
    BrainBackend.openAiCompatible => OpenAiCompatibleProvider(
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
    ),
  };

  Brain buildBrain() => Brain(
    provider: buildProvider(),
    persona: CharacterStore.instance.current.value.persona,
  );
}

class SettingsStore {
  SettingsStore._();

  static const _kBackend = 'brain.backend';
  static const _kBaseUrl = 'brain.baseUrl';
  static const _kModel = 'brain.model';
  static const _kApiKey = 'brain.apiKey';
  static const _kTranscriptionBaseUrl = 'brain.transcriptionBaseUrl';
  static const _kTranscriptionModel = 'brain.transcriptionModel';
  static const _kTtsBaseUrl = 'brain.ttsBaseUrl';
  static const _kTtsModel = 'brain.ttsModel';
  static const _kTtsVoice = 'brain.ttsVoice';

  static const _secure = FlutterSecureStorage();

  static Future<BrainSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final backendName = prefs.getString(_kBackend);
    final apiKey = await _secure.read(key: _kApiKey);
    return BrainSettings(
      backend: BrainBackend.values.asNameMap()[backendName] ??
          BrainSettings.defaults.backend,
      baseUrl: prefs.getString(_kBaseUrl) ?? BrainSettings.defaults.baseUrl,
      model: prefs.getString(_kModel) ?? BrainSettings.defaults.model,
      apiKey: apiKey,
      transcriptionBaseUrl: prefs.getString(_kTranscriptionBaseUrl),
      transcriptionModel:
          prefs.getString(_kTranscriptionModel) ?? 'whisper-1',
      ttsBaseUrl: prefs.getString(_kTtsBaseUrl),
      ttsModel: prefs.getString(_kTtsModel) ?? 'tts-1',
      ttsVoice: prefs.getString(_kTtsVoice) ?? 'alloy',
    );
  }

  static Future<void> save(BrainSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBackend, settings.backend.name);
    await prefs.setString(_kBaseUrl, settings.baseUrl);
    await prefs.setString(_kModel, settings.model);
    final tUrl = settings.transcriptionBaseUrl;
    if (tUrl == null || tUrl.isEmpty) {
      await prefs.remove(_kTranscriptionBaseUrl);
    } else {
      await prefs.setString(_kTranscriptionBaseUrl, tUrl);
    }
    await prefs.setString(_kTranscriptionModel, settings.transcriptionModel);
    final ttsUrl = settings.ttsBaseUrl;
    if (ttsUrl == null || ttsUrl.isEmpty) {
      await prefs.remove(_kTtsBaseUrl);
    } else {
      await prefs.setString(_kTtsBaseUrl, ttsUrl);
    }
    await prefs.setString(_kTtsModel, settings.ttsModel);
    await prefs.setString(_kTtsVoice, settings.ttsVoice);
    final key = settings.apiKey;
    if (key == null || key.isEmpty) {
      await _secure.delete(key: _kApiKey);
    } else {
      await _secure.write(key: _kApiKey, value: key);
    }
  }
}
