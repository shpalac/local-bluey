import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/stt.dart';

class Audio implements File {
  int accesses = 0;
  Completer<bool>? existence;
  @override
  String get path => '/fixture/audio.m4a';
  @override
  Future<bool> exists() async {
    accesses++;
    return existence == null ? true : await existence!.future;
  }

  @override
  Future<int> length() async {
    accesses++;
    return 3;
  }

  @override
  bool existsSync() => true;
  @override
  int lengthSync() => 3;
  @override
  Stream<List<int>> openRead([int? start, int? end]) => Stream.value([1, 2, 3]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client extends http.BaseClient {
  final headers = Completer<http.StreamedResponse>();
  int sends = 0;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sends++;
    expect(request.followRedirects, isFalse);
    return headers.future;
  }

  @override
  void close() {
    closed = true;
  }
}

HttpSttProvider provider({
  required http.Client client,
  Duration timeout = HttpSttProvider.requestTimeout,
}) => HttpSttProvider(
  client: client,
  timeout: timeout,
  multipartFile: (audio) async =>
      http.MultipartFile.fromBytes('file', [1, 2, 3], filename: 'audio.m4a'),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PrivacyGuard.debugLocalOnlyOverride = false);
  tearDown(() => PrivacyGuard.debugLocalOnlyOverride = null);
  const settings = SttSettings(
    baseUrl: 'http://localhost:9/v1',
    model: 'm',
    apiKey: 'stt-key',
  );
  for (final lateError in [false, true]) {
    test(
      'entered send expires before late ${lateError ? 'error' : 'headers'}, releases late body',
      () {
        fakeAsync((zone) {
          final client = Client(), audio = Audio();
          Object? error;
          String? text;
          provider(client: client, timeout: const Duration(seconds: 3))
              .transcribe(audio, settings)
              .then(
                (value) {
                  text = value;
                },
                onError: (Object e) {
                  error = e;
                },
              );
          zone.flushMicrotasks();
          expect(client.sends, 1);
          zone.elapse(const Duration(milliseconds: 2999));
          expect(error, isNull);
          zone.elapse(const Duration(milliseconds: 1));
          expect(
            error,
            isA<SttException>().having(
              (e) => e.kind,
              'kind',
              SttErrorKind.timeout,
            ),
          );
          var cancelled = false;
          final body = StreamController<List<int>>(
            onCancel: () {
              cancelled = true;
            },
          );
          if (lateError) {
            client.headers.completeError(StateError('late send'));
          } else {
            client.headers.complete(http.StreamedResponse(body.stream, 200));
          }
          zone.flushMicrotasks();
          if (!lateError) expect(cancelled, isTrue);
          expect(text, isNull);
          expect(client.closed, isFalse);
          body.close();
          zone.flushMicrotasks();
        });
      },
    );
    test(
      'late headers leave only original budget; stalled chunk body cancels before late ${lateError ? 'error' : 'success'}',
      () {
        fakeAsync((zone) {
          final client = Client();
          var cancelled = false;
          Object? error;
          String? text;
          final body = StreamController<List<int>>(
            onCancel: () {
              cancelled = true;
            },
          );
          provider(client: client, timeout: const Duration(seconds: 3))
              .transcribe(Audio(), settings)
              .then(
                (value) {
                  text = value;
                },
                onError: (Object e) {
                  error = e;
                },
              );
          zone.flushMicrotasks();
          expect(client.sends, 1);
          zone.elapse(const Duration(seconds: 2));
          client.headers.complete(http.StreamedResponse(body.stream, 200));
          zone.flushMicrotasks();
          body.add(utf8.encode('{"text":'));
          zone.flushMicrotasks();
          zone.elapse(const Duration(milliseconds: 999));
          expect(error, isNull);
          expect(cancelled, isFalse);
          zone.elapse(const Duration(milliseconds: 1));
          expect(
            error,
            isA<SttException>().having(
              (e) => e.kind,
              'kind',
              SttErrorKind.timeout,
            ),
          );
          expect(cancelled, isTrue);
          expect(body.hasListener, isFalse);
          expect(text, isNull);
          if (lateError) {
            body.addError(StateError('late body'));
          } else {
            body.add(utf8.encode('"late"}'));
          }
          body.close();
          zone.flushMicrotasks();
          expect(text, isNull);
          expect(client.closed, isFalse);
        });
      },
    );
  }
  test('preparation shares deadline and cannot send after release', () {
    fakeAsync((zone) {
      final client = Client(), audio = Audio()..existence = Completer<bool>();
      Object? error;
      provider(client: client, timeout: const Duration(seconds: 3))
          .transcribe(audio, settings)
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      zone.flushMicrotasks();
      expect(audio.accesses, 1);
      zone.elapse(const Duration(seconds: 3));
      expect(error, isA<SttException>());
      audio.existence!.complete(true);
      zone.flushMicrotasks();
      expect(client.sends, 0);
    });
  });
  for (final bodyText in [
    '{"text":" hi "}',
    'not json',
    '{"missing":"text"}',
  ]) {
    test('normal chunked body settled correctly: $bodyText', () {
      fakeAsync((zone) {
        final client = Client();
        var cancelled = false;
        String? text;
        Object? error;
        final body = StreamController<List<int>>(
          onCancel: () {
            cancelled = true;
          },
        );
        provider(client: client, timeout: const Duration(seconds: 3))
            .transcribe(Audio(), settings)
            .then(
              (v) {
                text = v;
              },
              onError: (Object e) {
                error = e;
              },
            );
        zone.flushMicrotasks();
        client.headers.complete(http.StreamedResponse(body.stream, 200));
        zone.flushMicrotasks();
        final bytes = utf8.encode(bodyText);
        body.add(bytes.sublist(0, 2));
        body.add(bytes.sublist(2));
        body.close();
        zone.flushMicrotasks();
        if (bodyText.startsWith('{"text"')) {
          expect(text, 'hi');
          expect(error, isNull);
        } else {
          expect(
            error,
            isA<SttException>().having(
              (e) => e.kind,
              'kind',
              SttErrorKind.decoderError,
            ),
          );
        }
        expect(cancelled, isTrue);
        expect(client.closed, isFalse);
        zone.elapse(const Duration(seconds: 4));
        expect(text, bodyText.startsWith('{"text"') ? 'hi' : null);
      });
    });
  }
  test('body error propagates, listener releases, client remains open', () {
    fakeAsync((zone) {
      final client = Client();
      Object? error;
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      provider(client: client)
          .transcribe(Audio(), settings)
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      zone.flushMicrotasks();
      client.headers.complete(http.StreamedResponse(body.stream, 200));
      zone.flushMicrotasks();
      body.addError(StateError('body'));
      zone.flushMicrotasks();
      zone.elapse(Duration.zero);
      expect(error, isStateError);
      expect(cancelled, isTrue);
      expect(client.closed, isFalse);
      body.close();
      zone.flushMicrotasks();
    });
  });
  test('pending body cancellation cannot delay observable deadline', () {
    fakeAsync((zone) {
      final client = Client(), cancellation = Completer<void>();
      var cancelled = false;
      Object? error;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
          return cancellation.future;
        },
      );
      provider(client: client, timeout: const Duration(seconds: 3))
          .transcribe(Audio(), settings)
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      zone.flushMicrotasks();
      client.headers.complete(http.StreamedResponse(body.stream, 200));
      zone.flushMicrotasks();
      zone.elapse(const Duration(seconds: 3));
      expect(cancelled, isTrue);
      expect(
        error,
        isA<SttException>().having((e) => e.kind, 'kind', SttErrorKind.timeout),
      );
      expect(cancellation.isCompleted, isFalse);
      expect(client.closed, isFalse);
      cancellation.completeError(StateError('cancel failure'));
      zone.flushMicrotasks();
      body.close();
      zone.flushMicrotasks();
    });
  });
  test('entered multipart preparation cannot upload after expiry', () {
    fakeAsync((zone) {
      final client = Client(), prepared = Completer<http.MultipartFile>();
      Object? error;
      HttpSttProvider(
            client: client,
            timeout: const Duration(seconds: 3),
            multipartFile: (_) => prepared.future,
          )
          .transcribe(Audio(), settings)
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      zone.flushMicrotasks();
      zone.elapse(const Duration(seconds: 3));
      expect(error, isA<SttException>());
      prepared.complete(http.MultipartFile.fromBytes('file', [1, 2, 3]));
      zone.flushMicrotasks();
      expect(client.sends, 0);
      expect(client.closed, isFalse);
    });
  });
  test('privacy refusal before any file or send access', () {
    fakeAsync((zone) {
      PrivacyGuard.debugLocalOnlyOverride = true;
      final audio = Audio(), client = Client();
      Object? error;
      provider(client: client)
          .transcribe(
            audio,
            const SttSettings(baseUrl: 'https://remote.invalid'),
          )
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      zone.flushMicrotasks();
      expect(
        error,
        isA<SttException>().having(
          (e) => e.kind,
          'kind',
          SttErrorKind.unreachable,
        ),
      );
      expect(audio.accesses, 0);
      expect(client.sends, 0);
    });
  });
}
