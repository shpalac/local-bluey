import 'package:flutter/material.dart';

import '../llm/llm_provider.dart';
import '../llm/ollama_provider.dart' show LlmException;
import '../services/settings_store.dart';

/// Provider picker + connection details for the brain. The API key is stored
/// in the Keychain, never in plain preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  final _transcriptionBaseUrl = TextEditingController();
  final _transcriptionModel = TextEditingController();
  final _ttsBaseUrl = TextEditingController();
  final _ttsModel = TextEditingController();
  final _ttsVoice = TextEditingController();
  BrainBackend _backend = BrainSettings.defaults.backend;
  bool _loaded = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    SettingsStore.load().then((settings) {
      setState(() {
        _backend = settings.backend;
        _baseUrl.text = settings.baseUrl;
        _model.text = settings.model;
        _apiKey.text = settings.apiKey ?? '';
        _transcriptionBaseUrl.text = settings.transcriptionBaseUrl ?? '';
        _transcriptionModel.text = settings.transcriptionModel;
        _ttsBaseUrl.text = settings.ttsBaseUrl ?? '';
        _ttsModel.text = settings.ttsModel;
        _ttsVoice.text = settings.ttsVoice;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _transcriptionBaseUrl.dispose();
    _transcriptionModel.dispose();
    _ttsBaseUrl.dispose();
    _ttsModel.dispose();
    _ttsVoice.dispose();
    super.dispose();
  }

  BrainSettings _current() => BrainSettings(
    backend: _backend,
    baseUrl: _baseUrl.text.trim(),
    model: _model.text.trim(),
    apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
    transcriptionBaseUrl: _transcriptionBaseUrl.text.trim().isEmpty
        ? null
        : _transcriptionBaseUrl.text.trim(),
    transcriptionModel: _transcriptionModel.text.trim().isEmpty
        ? 'whisper-1'
        : _transcriptionModel.text.trim(),
    ttsBaseUrl: _ttsBaseUrl.text.trim().isEmpty
        ? null
        : _ttsBaseUrl.text.trim(),
    ttsModel: _ttsModel.text.trim().isEmpty ? 'tts-1' : _ttsModel.text.trim(),
    ttsVoice: _ttsVoice.text.trim().isEmpty ? 'alloy' : _ttsVoice.text.trim(),
  );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await SettingsStore.save(_current());
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final reply = await _current().buildProvider().chat(
        const [LlmMessage('user', 'Say "ok" and nothing else.')],
      );
      setState(() => _testResult = 'Connected: ${reply.trim()}');
    } on LlmException catch (e) {
      setState(() => _testResult = 'Failed: $e');
    } catch (e) {
      setState(() => _testResult = 'Failed: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final needsKey = _backend == BrainBackend.openAiCompatible;
    return Scaffold(
      appBar: AppBar(title: const Text('Brain settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SegmentedButton<BrainBackend>(
              segments: const [
                ButtonSegment(
                  value: BrainBackend.ollama,
                  label: Text('Ollama'),
                ),
                ButtonSegment(
                  value: BrainBackend.openAiCompatible,
                  label: Text('OpenAI-compatible'),
                ),
              ],
              selected: {_backend},
              onSelectionChanged: (sel) => setState(() => _backend = sel.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _baseUrl,
              decoration: InputDecoration(
                labelText: 'Base URL',
                hintText: _backend == BrainBackend.ollama
                    ? 'http://localhost:11434'
                    : 'http://localhost:1234/v1',
              ),
              keyboardType: TextInputType.url,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Base URL is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _model,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'llama3.2',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Model is required' : null,
            ),
            if (needsKey) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiKey,
                decoration: const InputDecoration(
                  labelText: 'API key',
                  hintText: 'Stored in the Keychain',
                ),
                obscureText: true,
              ),
            ],
            const SizedBox(height: 24),
            Text('Transcription', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _transcriptionBaseUrl,
              decoration: const InputDecoration(
                labelText: 'Transcription base URL (optional)',
                hintText: 'Defaults to the brain base URL',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _transcriptionModel,
              decoration: const InputDecoration(labelText: 'Transcription model'),
            ),
            const SizedBox(height: 24),
            Text('Speech', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _ttsBaseUrl,
              decoration: const InputDecoration(
                labelText: 'TTS base URL (optional)',
                hintText: 'Defaults to the brain base URL',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ttsModel,
              decoration: const InputDecoration(labelText: 'TTS model'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ttsVoice,
              decoration: const InputDecoration(labelText: 'TTS voice'),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                FilledButton(onPressed: _save, child: const Text('Save')),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _testing ? null : _test,
                  child: Text(_testing ? 'Testing…' : 'Test connection'),
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 16),
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.startsWith('Connected')
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

