import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_bluey/services/audio_capture.dart';
import 'package:local_bluey/services/egress_monitor.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/stt.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/wake_word.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bytes = [0, 1, 2, 3, 255];
const _base = 'http://localhost:9137/v1';

class _Spotter extends WakeWordSpotter {
  _Spotter(this.value);
  final double value;
  int calls = 0;
  @override
  Future<double> score(File audioWindow) async {
    calls++;
    return value;
  }
}

/// Synthetic only. No IO client, fallback destination or real transport.
class _Client extends http.BaseClient {
  _Client(this.text);
  final String text;
  final entered = Completer<void>(), release = Completer<void>();
  final bodies = <List<int>>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.toString() != '$_base/audio/transcriptions' ||
        request.method != 'POST' ||
        request is! http.MultipartRequest) {
      throw StateError('network forbidden: unexpected synthetic request');
    }
    expect(request.fields['model'], 'synthetic-stt');
    expect(request.files.single.length, _bytes.length);
    expect(request.followRedirects, isFalse);
    bodies.add(await request.finalize().toBytes());
    entered.complete();
    await release.future;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'text': text}))),
      200,
    );
  }

  void finish() {
    if (!release.isCompleted) release.complete();
  }
}

class _Recorder implements RecorderDriver {
  String? path;
  int open = 0;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start(String path) async {
    this.path = path;
    open++;
    await File(path).writeAsBytes(_bytes);
  }

  @override
  Future<String?> stop() async {
    final value = path;
    if (value != null) {
      open--;
      path = null;
    }
    return value;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tmp;
  late File audio;
  late bool? oldPrivacy;
  late String oldLanguage;
  final monitor = EgressMonitor.instance;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wake-egress-');
    messenger.setMockMethodCallHandler(pathChannel, (_) async => tmp.path);
    messenger.setMockMethodCallHandler(secureChannel, (_) async => null);
    oldPrivacy = PrivacyGuard.debugLocalOnlyOverride;
    PrivacyGuard.debugLocalOnlyOverride = null;
    oldLanguage = Strings.speechLanguage;
    Strings.speechLanguage = 'auto';
    SharedPreferences.setMockInitialValues({
      'stt.baseUrl': _base,
      'stt.model': 'synthetic-stt',
      'privacy.localOnly': true,
      'wake_word.enabled': true,
    });
    await monitor.clear();
    audio = await File('${tmp.path}/synthetic.m4a').writeAsBytes(_bytes);
  });
  tearDown(() async {
    await monitor.load();
    await monitor.clear();
    PrivacyGuard.debugLocalOnlyOverride = oldPrivacy;
    Strings.speechLanguage = oldLanguage;
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(pathChannel, null);
    messenger.setMockMethodCallHandler(secureChannel, null);
    await tmp.delete(recursive: true);
  });

  for (final nullEngine in [false, true]) {
    test(
      'trusted injected actual HTTP provider unused for ${nullEngine ? 'null engine' : 'low score'}',
      () async {
        final client = _Client('hey bluey');
        final spotter = _Spotter(0.2);
        final service = WakeWordService(
          spotter: nullEngine ? null : spotter,
          transcription: HttpSttProvider(client: client),
        );
        var wakes = 0;
        service.onWake = () => wakes++;
        try {
          expect(await service.scoreAndMaybeWake(audio), isFalse);
          await monitor.load();
          expect(client.bodies, isEmpty);
          expect(client.entered.isCompleted, isFalse);
          expect(monitor.entries, isEmpty);
          expect(wakes, 0);
          expect(spotter.calls, nullEngine ? 0 : 1);
        } finally {
          client.finish();
          await service.stop();
          client.close();
        }
      },
    );
  }
  for (final match in [true, false]) {
    test(
      'trusted injected local HTTP confirmation ${match ? 'matches' : 'does not match'} with pre-send row',
      () async {
        final client = _Client(
          match ? 'HEY BLUEY synthetic' : 'different synthetic phrase',
        );
        final service = WakeWordService(
          spotter: _Spotter(0.9),
          transcription: HttpSttProvider(client: client),
        );
        var wakes = 0;
        service.onWake = () => wakes++;
        final scoring = service.scoreAndMaybeWake(audio);
        try {
          await client.entered.future;
          await monitor.load();
          expect(monitor.entries.single.kind, 'transcription');
          expect(monitor.entries.single.host, 'localhost');
          expect(monitor.entries.single.bytes, _bytes.length);
          expect(client.bodies.single.length, greaterThan(_bytes.length));
          expect(
            latin1.decode(client.bodies.single),
            contains(latin1.decode(_bytes)),
          );
          expect(wakes, 0);
          client.finish();
          expect(await scoring, match);
          expect(wakes, match ? 1 : 0);
        } finally {
          client.finish();
          await scoring;
          await service.stop();
          client.close();
        }
      },
    );
  }

  test('actual stop joins entered trusted HTTP confirmation and suppresses late wake', () async {
    final client = _Client('hey bluey');
    final rec = _Recorder();
    final capture = AudioCapture(driver: rec, tempDirProvider: () async => tmp);
    final windowEntered = Completer<void>(), windowRelease = Completer<void>();
    final service = WakeWordService(
      spotter: _Spotter(0.9),
      capture: capture,
      transcription: HttpSttProvider(client: client),
      windowDelay: (_) {
        windowEntered.complete();
        return windowRelease.future;
      },
    );
    var wakes = 0;
    service.onWake = () => wakes++;
    try {
      await service.start();
      await windowEntered.future;
      expect(rec.open, 1);
      windowRelease.complete();
      await client.entered.future;
      await monitor.load();
      expect(monitor.entries.single.bytes, _bytes.length);
      expect(rec.open, 0);
      final candidate = tmp.listSync().whereType<File>().singleWhere(
        (file) => file.path.contains('bluey_hold_'),
      );
      var joined = false;
      final stopping = service.stop().then((_) => joined = true);
      expect(service.listening.value, isFalse);
      await monitor.load(); // Independent queue barrier while HTTP stays held.
      expect(joined, isFalse);
      expect(candidate.existsSync(), isTrue);
      client.finish();
      await stopping;
      expect(joined, isTrue);
      expect(wakes, 0);
      expect(candidate.existsSync(), isFalse);
      expect(capture.cleanupPending, isFalse);
      expect(
        monitor.entries,
        hasLength(1),
      ); // Stop does not undo entered metadata.
    } finally {
      if (!windowRelease.isCompleted) windowRelease.complete();
      client.finish();
      await service.stop();
      await capture.dispose();
      client.close();
    }
  });

  for (final score in [0.2, 0.9]) {
    test(
      'noninjected remote score $score skips actual IO provider creation',
      () async {
        SharedPreferences.setMockInitialValues({
          'stt.baseUrl': 'https://remote.synthetic.invalid/v1',
          'stt.model': 'synthetic-stt',
          'privacy.localOnly': false,
        });
        var ioCreates = 0;
        final service = WakeWordService(spotter: _Spotter(score));
        var wakes = 0;
        service.onWake = () => wakes++;
        try {
          await HttpOverrides.runZoned(
            () async {
              // Calibrate the exact IO client construction path used by production
              // HttpSttProvider. Any attempted creation is blocked before sockets.
              expect(() => HttpSttProvider(), throwsStateError);
              expect(ioCreates, 1);
              ioCreates = 0;
              expect(await service.scoreAndMaybeWake(audio), score >= 0.6);
              expect(ioCreates, 0);
            },
            createHttpClient: (_) {
              ioCreates++;
              throw StateError('all synthetic IO client creation blocked');
            },
          );
          await monitor.load();
          expect(monitor.entries, isEmpty);
          expect(wakes, score >= 0.6 ? 1 : 0);
        } finally {
          await service.stop();
        }
      },
    );
  }
}
