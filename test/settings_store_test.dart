import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SettingsStore.debugSecureStorage = null;
    SettingsStore.lastSecureStorageWarning = null;
  });

  group('secure-storage failures (#123)', () {
    test('load returns settings without a key when the store throws', () async {
      // No platform channel in tests: the real FlutterSecureStorage throws
      // MissingPluginException, which is exactly the locked-keychain case.
      final settings = await SettingsStore.load();
      expect(settings.apiKey, isNull);
      expect(settings.backend, BrainSettings.defaults.backend);
      expect(SettingsStore.lastSecureStorageWarning, isNotNull);
    });

    test('a healthy store loads the key and clears the warning', () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'read') {
              return {'brain.apiKey': 'sk-test'}[call.arguments['key']];
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final settings = await SettingsStore.load();
      expect(settings.apiKey, 'sk-test');
      expect(SettingsStore.lastSecureStorageWarning, isNull);
    });
  });

  group('copyWith clearing (#123)', () {
    const withKey = BrainSettings(
      backend: BrainBackend.openAiCompatible,
      baseUrl: 'https://api.example.com',
      model: 'gpt-test',
      apiKey: 'sk-1',
      transcriptionBaseUrl: 'https://stt.example.com',
      ttsBaseUrl: 'https://tts.example.com',
    );

    test('clearApiKey removes the key', () {
      expect(withKey.copyWith(clearApiKey: true).apiKey, isNull);
    });

    test('clear flags remove endpoint overrides', () {
      final cleared = withKey.copyWith(
        clearTranscriptionBaseUrl: true,
        clearTtsBaseUrl: true,
      );
      expect(cleared.transcriptionBaseUrl, isNull);
      expect(cleared.ttsBaseUrl, isNull);
      expect(cleared.apiKey, 'sk-1'); // untouched
    });

    test('without flags, copyWith keeps values as before', () {
      final kept = withKey.copyWith(model: 'other');
      expect(kept.apiKey, 'sk-1');
      expect(kept.transcriptionBaseUrl, 'https://stt.example.com');
    });
  });

  group('save ordering (#123)', () {
    test('save writes the schema version', () async {
      // Secure write throws without a channel; that failure must leave prefs
      // untouched (all-or-nothing).
      await expectLater(
        SettingsStore.save(BrainSettings.defaults.copyWith(apiKey: 'sk-x')),
        throwsStateError,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('brain.baseUrl'), isNull);
    });

    test('a healthy store saves everything plus the schema version', () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await SettingsStore.save(
        BrainSettings.defaults.copyWith(model: 'llama3.1', apiKey: 'sk-y'),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('brain.schemaVersion'), SettingsStore.schemaVersion);
      expect(prefs.getString('brain.model'), 'llama3.1');
    });
  });
}
