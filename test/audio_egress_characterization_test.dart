import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_bluey/services/egress_monitor.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:local_bluey/services/speech.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/stt.dart';
import 'package:shared_preferences/shared_preferences.dart';

const base = 'https://audio-fixture.invalid/v1';
const syntheticAudio = [0, 1, 2, 3, 255];
const text = 'שלום café 😀';
const stt = SttSettings(baseUrl: base, model: 'synthetic-stt');
const tts = BrainSettings(
  backend: BrainBackend.ollama,
  baseUrl: 'https://unused-brain.invalid',
  model: 'synthetic-brain',
  ttsBaseUrl: base,
  ttsModel: 'synthetic-tts',
  ttsVoice: 'fixture-voice',
);

/// Has no network fallback or IO client. Bytes are intercepted fixture bodies,
/// not wire bytes, remote receipt, upload cancellation or privacy proof.
class AudioClient extends http.BaseClient {
  AudioClient(this.speech, {this.status = 200});
  final bool speech;
  final int status;
  bool fail = false, closed = false;
  final entered = Completer<void>(), release = Completer<void>();
  final requests = <List<int>>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed ||
        request.method != 'POST' ||
        request.url.toString() !=
            '$base/audio/${speech ? 'speech' : 'transcriptions'}') {
      throw StateError('network forbidden: unexpected fixture request');
    }
    if (speech) {
      expect(request.headers['content-type'], startsWith('application/json'));
    } else {
      expect(request, isA<http.MultipartRequest>());
      final multipart = request as http.MultipartRequest;
      expect(multipart.fields, {'model': 'synthetic-stt', 'language': 'he'});
      expect(multipart.files.single.field, 'file');
      expect(multipart.files.single.length, syntheticAudio.length);
      expect(multipart.followRedirects, false);
    }
    final bytes = await request.finalize().toBytes();
    if (speech) {
      expect(
        utf8.decode(bytes),
        jsonEncode({
          'model': 'synthetic-tts',
          'voice': 'fixture-voice',
          'input': text,
          'response_format': 'mp3',
        }),
      );
    } else {
      final body = latin1.decode(bytes);
      expect(body, contains('name="model"\r\n\r\nsynthetic-stt'));
      expect(body, contains('name="language"\r\n\r\nhe'));
      expect(body, contains(latin1.decode(syntheticAudio)));
    }
    requests.add(bytes);
    entered.complete();
    await release.future;
    if (fail) throw StateError('synthetic transport failure');
    return http.StreamedResponse(
      Stream.value(
        speech ? [1, 2, 3] : utf8.encode('{"text":"fixture transcription"}'),
      ),
      status,
    );
  }

  void finish() {
    if (!release.isCompleted) release.complete();
  }

  @override
  void close() => closed = true;
}

class NoPlayback implements SpeechPlayback {
  @override
  Stream<void> completed(String path) => throw StateError('no playback');
  @override
  Future<void> play(String path) async => throw StateError('no playback');
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

Future<void> rows({
  required bool speech,
  required AudioClient client,
  required int count,
}) async {
  await EgressMonitor.instance.load(); // Ordered after older unawaited records.
  expect(EgressMonitor.instance.historyAvailable, true);
  final entries = EgressMonitor.instance.entries;
  expect(entries, hasLength(count));
  if (count == 0) return;
  expect(entries.single.host, 'audio-fixture.invalid');
  expect(entries.single.kind, speech ? 'tts' : 'transcription');
  expect(entries.single.bytes, speech ? text.length : syntheticAudio.length);
  expect(entries.single.bytes, lessThan(client.requests.single.length));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late File capture;
  late bool? previousOverride;
  late String previousLanguage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('audio-egress-486-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    SharedPreferences.setMockInitialValues({});
    previousOverride = PrivacyGuard.debugLocalOnlyOverride;
    previousLanguage = Strings.speechLanguage;
    PrivacyGuard.debugLocalOnlyOverride = false;
    Strings.speechLanguage = 'he';
    capture = File('${directory.path}/synthetic.m4a');
    await capture.writeAsBytes(syntheticAudio);
    await EgressMonitor.instance.clear();
  });
  tearDown(() async {
    await EgressMonitor.instance.load();
    await EgressMonitor.instance.clear();
    if (await capture.exists()) await capture.delete();
    expect(await directory.list().toList(), isEmpty);
    PrivacyGuard.debugLocalOnlyOverride = previousOverride;
    Strings.speechLanguage = previousLanguage;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete();
    expect(await directory.exists(), false);
  });

  for (final speech in [false, true]) {
    final kind = speech ? 'TTS' : 'STT';
    for (final result in ['success', 'throw', 'status']) {
      test(
        '$kind held/$result retains before-send metadata not captured-body bytes',
        () async {
          final client = AudioClient(
            speech,
            status: result == 'status' ? 400 : 200,
          )..fail = result == 'throw';
          final service = speech
              ? SpeechService(client: client, playback: NoPlayback())
              : null;
          Object? failure, answer;
          final Future<Object> operation = speech
              ? service!.synthesize(text, tts)
              : HttpSttProvider(client: client).transcribe(capture, stt);
          final work = operation.then<void>(
            (value) => answer = value,
            onError: (Object error) {
              failure = error;
            },
          );
          addTearDown(() async {
            client.finish();
            await work;
            if (service != null) {
              await service.dispose();
            } else {
              client.close();
            }
            expect(client.closed, true);
          });
          await client.entered.future;
          expect(client.requests, hasLength(1));
          expect(answer, isNull);
          expect(failure, isNull);
          await rows(speech: speech, client: client, count: 1);
          client.finish();
          await work;
          if (result == 'success') {
            expect(failure, isNull);
            expect(answer, speech ? [1, 2, 3] : 'fixture transcription');
          } else if (speech) {
            expect(
              failure,
              isA<SpeechException>().having(
                (e) => e.message,
                'message',
                result == 'throw'
                    ? 'Speech request failed.'
                    : 'Speech HTTP 400.',
              ),
            );
          } else {
            expect(
              failure,
              result == 'throw'
                  ? isA<StateError>()
                  : isA<SttException>().having(
                      (e) => e.kind,
                      'kind',
                      SttErrorKind.httpError,
                    ),
            );
          }
          await rows(speech: speech, client: client, count: 1);
          expect(client.requests, hasLength(1));
        },
      );
    }
    test(
      '$kind local-only refusal happens before record and captured request',
      () async {
        PrivacyGuard.debugLocalOnlyOverride = true;
        final client = AudioClient(speech);
        final service = speech
            ? SpeechService(client: client, playback: NoPlayback())
            : null;
        addTearDown(() async {
          if (service != null) {
            await service.dispose();
          } else {
            client.close();
          }
        });
        await expectLater(
          speech
              ? service!.synthesize(text, tts)
              : HttpSttProvider(client: client).transcribe(capture, stt),
          throwsA(
            speech
                ? isA<SpeechException>()
                : isA<SttException>().having(
                    (e) => e.kind,
                    'kind',
                    SttErrorKind.unreachable,
                  ),
          ),
        );
        expect(client.requests, isEmpty);
        expect(client.entered.isCompleted, false);
        await rows(speech: speech, client: client, count: 0);
      },
    );
  }
  for (final stage in ['config', 'missing', 'empty']) {
    test('STT $stage refuses before metadata and captured request', () async {
      final client = AudioClient(false);
      addTearDown(client.close);
      if (stage == 'missing') await capture.delete();
      if (stage == 'empty') await capture.writeAsBytes([]);
      await expectLater(
        HttpSttProvider(client: client)
            .transcribe(capture, stage == 'config' ? const SttSettings() : stt),
        throwsA(
          isA<SttException>().having(
            (e) => e.kind,
            'kind',
            SttErrorKind.modelUnavailable,
          ),
        ),
      );
      expect(client.requests, isEmpty);
      expect(client.entered.isCompleted, false);
      await rows(speech: false, client: client, count: 0);
    });
  }
}
