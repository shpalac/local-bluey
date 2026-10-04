import 'package:flutter/material.dart';

import '../llm/llm_provider.dart';
import '../llm/ollama_provider.dart' show LlmException;
import '../services/haptics.dart';
import '../services/perf_monitor.dart';
import '../services/privacy_guard.dart';
import '../services/safety_gate.dart';
import '../services/strings.dart';
import '../services/settings_store.dart';
import 'data_privacy_section.dart';

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
  bool _localOnly = false;
  UiLanguage _uiLanguage = Strings.uiLanguage;
  String _speechLanguage = Strings.speechLanguage;
  bool _testing = false;
  String? _testResult;
  final _allowlist = TextEditingController();
  final _gate = SafetyGate();
  bool _safetyEnabled = true;
  bool _perfOverlay = false;

  @override
  void initState() {
    super.initState();
    PrivacyGuard.isLocalOnly().then((v) {
      if (mounted) setState(() => _localOnly = v);
    });
    _gate.allowlist().then((v) {
      if (mounted) setState(() => _allowlist.text = v.join(', '));
    });
    _gate.isEnabled().then((v) {
      if (mounted) setState(() => _safetyEnabled = v);
    });
    PerfMonitor.instance.isOverlayEnabled().then((v) {
      if (mounted) setState(() => _perfOverlay = v);
    });
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
    _allowlist.dispose();
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
    await _gate.setEnabled(_safetyEnabled);
    await _gate.setAllowlist(
      _allowlist.text
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet(),
    );
    await PerfMonitor.instance.setOverlayEnabled(_perfOverlay);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final reply = await _current().buildProvider().chat(const [
        LlmMessage('user', 'Say "ok" and nothing else.'),
      ]);
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
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Base URL is required'
                  : null,
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
            Text('Language', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<UiLanguage>(
              initialValue: _uiLanguage,
              decoration: const InputDecoration(labelText: 'UI language'),
              items: const [
                DropdownMenuItem(
                  value: UiLanguage.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(
                  value: UiLanguage.english,
                  child: Text('English'),
                ),
                DropdownMenuItem(
                  value: UiLanguage.hebrew,
                  child: Text('עברית'),
                ),
              ],
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _uiLanguage = v);
                await Strings.setUiLanguage(v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _speechLanguage,
              decoration: const InputDecoration(
                labelText: 'Speech language (transcription)',
              ),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Auto-detect')),
                DropdownMenuItem(value: 'he', child: Text('עברית')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _speechLanguage = v);
                await Strings.setSpeechLanguage(v);
              },
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Local-only mode'),
              subtitle: const Text(
                'Refuse providers that send data off this Mac',
              ),
              value: _localOnly,
              onChanged: (v) async {
                setState(() => _localOnly = v);
                await PrivacyGuard.setLocalOnly(v);
              },
            ),
            SwitchListTile(
              title: const Text('Safety gate'),
              subtitle: const Text(
                'Confirm risky actions; kill switch and app allowlist',
              ),
              value: _safetyEnabled,
              onChanged: (v) => setState(() => _safetyEnabled = v),
            ),
            TextFormField(
              controller: _allowlist,
              decoration: const InputDecoration(
                labelText: 'App allowlist (comma separated, empty = all)',
              ),
            ),
            SwitchListTile(
              title: const Text('Performance overlay'),
              subtitle: const Text(
                'Show live stage timings on the face screen',
              ),
              value: _perfOverlay,
              onChanged: (v) => setState(() => _perfOverlay = v),
            ),
            const SizedBox(height: 24),
            Text(
              'Transcription',
              style: Theme.of(context).textTheme.titleSmall,
            ),
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
              decoration: const InputDecoration(
                labelText: 'Transcription model',
              ),
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
            const DataPrivacySection(),
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

/// Phone-remote haptics toggle (#88), persisted via RemoteHaptics.
class _HapticsTile extends StatefulWidget {
  const _HapticsTile();

  @override
  State<_HapticsTile> createState() => _HapticsTileState();
}

class _HapticsTileState extends State<_HapticsTile> {
  bool _enabled = RemoteHaptics.instance.enabled;

  @override
  void initState() {
    super.initState();
    RemoteHaptics.instance.load().then((_) {
      if (mounted) setState(() => _enabled = RemoteHaptics.instance.enabled);
    });
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: const Icon(Icons.vibration),
    title: const Text('Haptics'),
    subtitle: const Text('Touch feedback on hold, answers, and connect.'),
    value: _enabled,
    onChanged: (value) {
      setState(() => _enabled = value);
      RemoteHaptics.instance.setEnabled(value);
    },
  );
}
