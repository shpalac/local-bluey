import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/egress_monitor.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:local_bluey/services/stt.dart';
import 'package:shared_preferences/shared_preferences.dart';

const brainUrl = 'http://localhost:11434';
const localStt = 'http://127.0.0.1:9000/v1';
const remoteStt = 'https://active-stt.invalid/v1';
const legacyRemote = 'https://legacy-stt.invalid/v1';
final fixtureNow = DateTime.utc(2026, 10, 11);

/// No platform/keychain calls; unexpected credential access fails locally.
class SyntheticSecureStore extends FlutterSecureStorage {
  final reads = <String>[];
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    expect(key, anyOf('stt.apiKey', 'brain.apiKey'));
    reads.add(key);
    return null;
  }
}

class IsolatedHistory implements EgressStorage {
  String? contents;
  bool unreadable = false;
  int reads = 0;
  @override
  Future<String?> read() async {
    reads++;
    if (unreadable) throw StateError('synthetic unavailable history');
    return contents;
  }

  @override
  Future<void> write(String value) async => contents = value;
  @override
  Future<void> delete() async => contents = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyntheticSecureStore secure;
  late IsolatedHistory history;
  late EgressMonitor monitor;
  late int retention;
  late String? previousWarning;
  setUp(() {
    // Standalone test-isolate baseline is empty mock prefs/default secure seams.
    SharedPreferences.setMockInitialValues({});
    secure = SyntheticSecureStore();
    SttSettings.debugSecureStorage = secure;
    SettingsStore.debugSecureStorage = secure;
    previousWarning = SettingsStore.lastSecureStorageWarning;
    retention = EgressMonitor.retentionDays;
    history = IsolatedHistory();
    monitor = EgressMonitor(storage: history, now: () => fixtureNow);
  });
  tearDown(() async {
    await monitor.load(); // Drain older ordered operations before reset.
    await monitor.clear();
    expect(history.contents, isNull);
    expect(monitor.entries, isEmpty);
    SttSettings.debugSecureStorage = null;
    SettingsStore.debugSecureStorage = null;
    SettingsStore.lastSecureStorageWarning = previousWarning;
    EgressMonitor.retentionDays = retention;
    SharedPreferences.setMockInitialValues({});
  });

  Future<({SttSettings active, BrainSettings legacy})> configuration({
    String? activeUrl,
    String? legacyUrl,
    String brain = brainUrl,
    SttProviderKind kind = SttProviderKind.http,
  }) async {
    final values = <String, Object>{
      'stt.migratedFromBrain': true,
      'stt.kind': kind.name,
      'stt.model': 'synthetic-stt',
      'stt.baseUrl': ?activeUrl,
      'brain.backend': BrainBackend.ollama.name,
      'brain.baseUrl': brain,
      'brain.model': 'synthetic-brain',
      'brain.ttsBaseUrl': localStt,
      'brain.transcriptionBaseUrl': ?legacyUrl,
    };
    SharedPreferences.setMockInitialValues(values);
    final active = await SttSettings.load();
    final legacy = await SettingsStore.load();
    expect(active.kind, kind);
    expect(active.baseUrl, activeUrl);
    expect(active.model, 'synthetic-stt');
    expect(active.apiKey, isNull);
    expect(legacy.transcriptionBaseUrl, legacyUrl);
    expect(legacy.baseUrl, brain);
    expect(secure.reads, ['stt.apiKey', 'brain.apiKey']);
    expect(SettingsStore.lastSecureStorageWarning, isNull);
    // Existing migrated marker prevents copying divergent legacy fields.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('stt.migratedFromBrain'), true);
    expect(prefs.getString('stt.baseUrl'), activeUrl);
    return (active: active, legacy: legacy);
  }

  test(
    'active remote STT plus legacy local and known empty yields no problems',
    () async {
      final config = await configuration(
        activeUrl: remoteStt,
        legacyUrl: localStt,
      );
      expect(config.active.baseUrl, remoteStt);
      expect(monitor.historyAvailable, false);
      expect(await monitor.offlineSelfTest(config.legacy), isEmpty);
      expect(history.reads, 1);
      expect(monitor.historyAvailable, true);
      expect(monitor.entries, isEmpty);
      // Empty result here cannot establish active-STT offline/no-egress readiness.
    },
  );
  test('active local STT does not suppress legacy remote warning', () async {
    final config = await configuration(
      activeUrl: localStt,
      legacyUrl: legacyRemote,
    );
    expect(await monitor.offlineSelfTest(config.legacy), [
      'transcription endpoint is remote: $legacyRemote',
    ]);
  });
  test('native configured kind still checks irrelevant legacy remote URL', () async {
    final config = await configuration(
      kind: SttProviderKind.nativeWhisper,
      legacyUrl: legacyRemote,
    );
    expect(config.active.kind, SttProviderKind.nativeWhisper);
    expect(config.active.baseUrl, isNull);
    expect(await monitor.offlineSelfTest(config.legacy), [
      'transcription endpoint is remote: $legacyRemote',
    ]);
    // Native implementation is a not-installed placeholder. No factory, audio,
    // asset, capability or native inference call is made by this configuration test.
  });
  test('absent legacy URL uses local brain not active remote STT', () async {
    final config = await configuration(activeUrl: remoteStt);
    expect(config.legacy.transcriptionBaseUrl, isNull);
    expect(await monitor.offlineSelfTest(config.legacy), isEmpty);
  });
  test(
    'absent legacy URL uses remote brain despite active local STT',
    () async {
      const remoteBrain = 'https://brain.invalid/v1';
      final config = await configuration(
        activeUrl: localStt,
        brain: remoteBrain,
      );
      expect(await monitor.offlineSelfTest(config.legacy), [
        'brain endpoint is remote: $remoteBrain',
        'transcription endpoint is remote: $remoteBrain',
      ]);
      // Dedicated local TTS remains independent of the brain fallback.
    },
  );
  test(
    'unreadable history warns even when legacy configuration is local',
    () async {
      final config = await configuration(
        activeUrl: remoteStt,
        legacyUrl: localStt,
      );
      history.unreadable = true;
      expect(await monitor.offlineSelfTest(config.legacy), [
        'Retained egress history is unavailable or incomplete.',
      ]);
      expect(monitor.historyAvailable, false);
      expect(monitor.entries, isEmpty);
      history.unreadable = false;
      expect(await monitor.offlineSelfTest(config.legacy), isEmpty);
      expect(monitor.historyAvailable, true);
      expect(history.reads, 2);
    },
  );
  test(
    'incomplete local metadata warns and preserves original fixture storage',
    () async {
      final config = await configuration(
        activeUrl: localStt,
        legacyUrl: localStt,
      );
      final row = jsonEncode(
        EgressEntry(
          host: 'localhost',
          kind: 'brain',
          bytes: 1,
          at: fixtureNow,
        ).toJson(),
      );
      history.contents = '$row\n{broken\n';
      final original = history.contents;
      expect(await monitor.offlineSelfTest(config.legacy), [
        'Retained egress history is unavailable or incomplete.',
      ]);
      expect(monitor.historyAvailable, false);
      expect(monitor.entries.single.host, 'localhost');
      expect(history.contents, original);
    },
  );
  test('retained remote label warns independent of local active configuration', () async {
    final config = await configuration(
      activeUrl: localStt,
      legacyUrl: localStt,
    );
    history.contents = jsonEncode(
      EgressEntry(
        host: 'past.invalid',
        kind: 'brain',
        bytes: 1,
        at: fixtureNow,
      ).toJson(),
    );
    expect(await monitor.offlineSelfTest(config.legacy), [
      'log shows past transmissions to: past.invalid',
    ]);
    expect(monitor.historyAvailable, true);
    expect(monitor.entries.single.host, 'past.invalid');
    // Host-label warning is not a measured transmission, DNS or receipt proof.
  });
}
