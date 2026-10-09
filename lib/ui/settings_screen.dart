import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../llm/llm_provider.dart';
import 'app_lock_tile.dart';
import 'theme.dart';
import 'troubleshooting_screen.dart';
import '../services/haptics.dart';
import '../services/perf_monitor.dart';
import '../services/native_control.dart';
import '../services/privacy_guard.dart';
import '../services/tutorial.dart';
import '../services/safety_gate.dart';
import '../services/strings.dart';
import '../services/action_log.dart';
import '../services/connection_error.dart';
import '../services/egress_monitor.dart';
import '../services/endpoint_assistant.dart';
import '../services/settings_store.dart';
import 'data_privacy_section.dart';
import 'hold_key_section.dart';
import 'watch_screen.dart';

/// Provider picker + connection details for the brain. The API key is stored
/// in the Keychain, never in plain preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onDeleteAll});

  /// Return the app to onboarding after all local data has been removed.
  final VoidCallback? onDeleteAll;

  /// Test seam: replaces the real chat call behind "Test connection" so
  /// widget tests can simulate failures without a network (#239).
  @visibleForTesting
  static Future<String> Function(BrainSettings settings)? debugTestChat;

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
  bool _deleting = false;
  int _loadGeneration = 0;
  bool _localOnly = false;
  UiLanguage _uiLanguage = Strings.uiLanguage;
  String _speechLanguage = Strings.speechLanguage;
  bool _testing = false;
  String? _testResult;
  ConnectionFailure? _testFailure;
  bool _detecting = false;
  String? _detectResult;
  final _allowlist = TextEditingController();
  final _gate = SafetyGate();
  bool _safetyEnabled = true;
  Duration? _gatePause; // time-boxed pause chosen in the warning (#133)
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
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final generation = ++_loadGeneration;
    final settings = await SettingsStore.load();
    if (!mounted || generation != _loadGeneration) return;
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
  }

  Future<void> _onDataCleared(String? storeId) async {
    if (storeId != null && storeId != 'settings') return;
    _loadGeneration++; // Reject any stale initial load before resetting.
    for (final controller in [
      _baseUrl,
      _model,
      _apiKey,
      _transcriptionBaseUrl,
      _transcriptionModel,
      _ttsBaseUrl,
      _ttsModel,
      _ttsVoice,
    ]) {
      controller.clear();
    }
    if (storeId == null) {
      widget.onDeleteAll?.call();
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    await _loadSettings();
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
    if (_deleting || !_loaded) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await SettingsStore.save(_current());
    } catch (e) {
      // #132: a failed save (e.g. locked keychain) must not pop silently.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save settings: $e')));
      }
      return;
    }
    await _gate.setEnabled(_safetyEnabled);
    if (!_safetyEnabled && _gatePause != null) {
      await _gate.pauseFor(_gatePause!);
    }
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
    final settings = _current();
    final url = settings.baseUrl;
    // #132: a connection test is egress too - honor Local-only and log it.
    if (_localOnly && !PrivacyGuard.isLocalUrl(url)) {
      setState(
        () => _testResult = 'Blocked by Local-only mode: $url is not local.',
      );
      return;
    }
    try {
      await EgressMonitor.instance.record(url, 'settings-test', 0);
    } catch (_) {}
    setState(() {
      _testing = true;
      _testResult = null;
      _testFailure = null;
    });
    try {
      final override = SettingsScreen.debugTestChat;
      final reply = override != null
          ? await override(settings)
          : await settings.buildProvider().chat(const [
              LlmMessage('user', 'Say "ok" and nothing else.'),
            ]);
      if (mounted) setState(() => _testResult = 'Connected: ${reply.trim()}');
    } catch (e) {
      // #239: plain message with the real host:port; raw text under Details.
      final failure = describeConnectionFailure(e, url);
      if (mounted) {
        setState(() {
          _testFailure = failure;
          _testResult = failure.summary;
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// #133: turning the gate off needs an explicit choice - pause for a
  /// while or really turn off - never a silent single tap.
  Future<void> _onGateSwitch(bool value) async {
    if (value) {
      setState(() {
        _safetyEnabled = true;
        _gatePause = null;
      });
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off action confirmations?'),
        content: const Text(
          'While off, click, type, key presses, drags, scrolls and app '
          'launches run WITHOUT asking you - including actions requested '
          'from your phone. On-screen text can steer the model, so this '
          'is the main defense against that.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Keep on'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'pause'),
            child: const Text('Pause 15 min'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'off'),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'off' || choice == 'pause') {
      setState(() {
        _safetyEnabled = false;
        _gatePause = choice == 'pause' ? const Duration(minutes: 15) : null;
      });
      // Recorded in the action log so the change is auditable (#133).
      try {
        await ActionLog.instance.record(
          ActionEntry(
            runId: 'settings',
            tool: 'safety_gate',
            arguments: const {},
            outcome: choice == 'pause'
                ? 'Confirmations paused for 15 minutes'
                : 'Confirmations turned off',
          ),
        );
      } catch (_) {}
    }
  }

  void _applyPreset(EndpointPreset preset) {
    setState(() {
      _backend = preset.backend;
      _baseUrl.text = preset.baseUrl;
      _model.text = preset.modelHint;
      if (!preset.requiresKey) _apiKey.text = '';
    });
  }

  Future<void> _detectOllama() async {
    setState(() {
      _detecting = true;
      _detectResult = null;
    });
    final detection = await EndpointAssistant().detectLocalOllama();
    if (!mounted) return;
    setState(() => _detecting = false);
    if (detection == null) {
      setState(
        () => _detectResult =
            'No Ollama on localhost:11434 - start it, then detect again.',
      );
      return;
    }
    final model = detection.suggestedModel ?? BrainSettings.defaults.model;
    setState(() {
      _backend = BrainBackend.ollama;
      _baseUrl.text = detection.baseUrl;
      _model.text = model;
      _detectResult =
          'Found Ollama with ${detection.models.length} model(s) - filled in $model.';
    });
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final preset in endpointPresets)
                  ActionChip(
                    label: Text(preset.label),
                    onPressed: () => _applyPreset(preset),
                  ),
                OutlinedButton.icon(
                  onPressed: _detecting ? null : _detectOllama,
                  icon: _detecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar, size: 18),
                  label: const Text('Detect local Ollama'),
                ),
              ],
            ),
            if (_detectResult != null) ...[
              const SizedBox(height: 8),
              Text(_detectResult!),
            ],
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
              onChanged: _onGateSwitch, // #133: off needs a real choice
            ),
            // Persistent indicator while the gate is off (#133).
            if (!_safetyEnabled)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _gatePause != null
                            ? 'Action confirmations are PAUSED '
                                  '(auto-resume in ${_gatePause!.inMinutes} min)'
                            : 'Action confirmations are OFF. '
                                  'Risky actions will not ask.',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
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
            const _AppearanceTile(),
            const AppLockTile(),
            const _HapticsTile(),
            if (defaultTargetPlatform == TargetPlatform.macOS)
              const HoldKeySection(),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('User guide'),
              subtitle: const Text('Gestures, voice flows, tools, privacy.'),
              onTap: () => NativeControl.openURL(
                'https://github.com/shpalac/local-bluey/blob/main/docs/USER_GUIDE.md',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Replay first-steps tutorial'),
              subtitle: const Text('Wake, ask, point - the guided demo.'),
              onTap: () {
                TutorialController.instance.reset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tutorial will show on the main screen.'),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: Text(Strings.t('Screen watching', 'צפייה במסך')),
              subtitle: Text(
                Strings.t(
                  'Consent, allowlist and session controls.',
                  'הסכמה, רשימת אפליקציות ובקרת סשנים.',
                ),
              ),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const WatchScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.build_outlined),
              title: const Text('Troubleshooting'),
              subtitle: const Text('Live checks and copyable diagnostics.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TroubleshootingScreen(),
                ),
              ),
            ),
            const ListTile(
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('Permissions in use'),
              subtitle: Text(
                'Microphone - hold-to-talk on the phone remote. '
                'Local network - finding your Mac. '
                'Each is requested only when its feature is first used; '
                'revoke any of them in system Settings.',
              ),
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
            DataPrivacySection(
              onCleared: _onDataCleared,
              onBusyChanged: (busy) {
                if (mounted) setState(() => _deleting = busy);
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                FilledButton(
                  onPressed: _deleting ? null : _save,
                  child: const Text('Save'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _testing ? null : _test,
                  child: Text(_testing ? 'Testing…' : 'Test connection'),
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _testFailure == null
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 18,
                      color: _testFailure == null
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testFailure == null
                            ? _testResult!
                            : 'Failed: ${_testResult!}',
                        style: TextStyle(
                          color: _testFailure == null
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_testFailure != null) ...[
                if (_testFailure!.suggestsLocalServer)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _detecting ? null : _detectOllama,
                          child: const Text('Detect local Ollama'),
                        ),
                        OutlinedButton(
                          onPressed: () => _applyPreset(
                            endpointPresets.firstWhere(
                              (p) => p.id == 'ollama',
                              orElse: () => endpointPresets.first,
                            ),
                          ),
                          child: const Text('Use Ollama preset (:11434)'),
                        ),
                      ],
                    ),
                  ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Details'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(_testFailure!.details),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Light/dark/system override (#87), persisted via ThemeController.
class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ThemeController.instance,
    builder: (context, _) => ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('Appearance'),
      trailing: DropdownButton<ThemeMode>(
        value: ThemeController.instance.mode,
        onChanged: (mode) {
          if (mode != null) ThemeController.instance.setMode(mode);
        },
        items: const [
          DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
          DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
        ],
      ),
    ),
  );
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
