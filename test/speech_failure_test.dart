import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_bluey/services/speech.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/settings_store.dart';

const settings = BrainSettings(
  backend: BrainBackend.openAiCompatible,
  baseUrl: 'http://localhost:8080/v1',
  model: 'm',
  apiKey: 'private-key',
);
const input = 'private-input';
Matcher safe(String message) =>
    isA<SpeechException>().having((e) => e.message, 'message', message);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PrivacyGuard.debugLocalOnlyOverride = false);
  tearDown(() => PrivacyGuard.debugLocalOnlyOverride = null);
  for (final body in [
    ' {"error":"private-key"}',
    '\n\t["private-input"]',
    '"/private/path"',
    'true',
    'false',
    'null',
    '42',
    '-2.5',
  ]) {
    test('valid JSON-shaped $body rejected safe exact detail', () async {
      final s = SpeechService(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(
        s.synthesize(input, settings),
        throwsA(safe('Speech returned a JSON response, not audio.')),
      );
    });
  }
  for (final type in [
    'application/json; charset=utf-8',
    'APPLICATION/JSON',
    'application/problem+json',
  ]) {
    for (final body in ['{}', '[]', '"private-key"', 'not json']) {
      test(
        'declared $type body $body rejected without inspecting error text',
        () async {
          final s = SpeechService(
            client: MockClient(
              (_) async =>
                  http.Response(body, 200, headers: {'content-type': type}),
            ),
          );
          await expectLater(
            s.synthesize(input, settings),
            throwsA(safe('Speech returned a JSON response, not audio.')),
          );
        },
      );
    }
  }
  for (final bytes in [
    [0xff, 0xfb, 0, 255],
    [73, 68, 51, 255],
    [123, 255],
    [91, 255],
    utf8.encode('{not JSON'),
    [1, 2, 3],
  ]) {
    test(
      'opaque binary/invalid JSON $bytes unchanged not codec claim',
      () async {
        var calls = 0;
        final s = SpeechService(
          client: MockClient((req) async {
            calls++;
            expect(req.url.path, '/v1/audio/speech');
            expect(req.headers['authorization'], 'Bearer private-key');
            expect(jsonDecode(req.body)['input'], input);
            expect(jsonDecode(req.body)['response_format'], 'mp3');
            return http.Response.bytes(bytes, 200);
          }),
        );
        expect(await s.synthesize(input, settings), bytes);
        expect(calls, 1);
      },
    );
  }
  test('HTTP private sentinel safely retains status and empty typed', () async {
    for (final status in [401, 503]) {
      await expectLater(
        SpeechService(
          client: MockClient(
            (_) async =>
                http.Response('private-key $input /private/path', status),
          ),
        ).synthesize(input, settings),
        throwsA(safe('Speech HTTP $status.')),
      );
    }
    await expectLater(
      SpeechService(
        client: MockClient((_) async => http.Response.bytes([], 200)),
      ).synthesize(input, settings),
      throwsA(safe('Speech returned empty audio.')),
    );
  });
  test('entered transport error typed safe no retry', () async {
    var calls = 0;
    final entered = Completer<void>(), release = Completer<http.Response>();
    final s = SpeechService(
      client: MockClient((_) {
        calls++;
        entered.complete();
        return release.future;
      }),
    );
    final checked = expectLater(
      s.synthesize(input, settings),
      throwsA(safe('Speech request failed.')),
    );
    await entered.future;
    release.completeError(
      http.ClientException('private-key $input /private/path'),
    );
    await checked;
    expect(calls, 1);
  });
  for (final error in [false, true]) {
    test(
      'fake deadline 60s late ${error ? 'error' : 'success'} consumed single request',
      () {
        fakeAsync((clock) {
          var calls = 0;
          Object? outcome;
          final release = Completer<http.Response>();
          final s = SpeechService(
            client: MockClient((_) {
              calls++;
              return release.future;
            }),
          );
          unawaited(
            s
                .synthesize(input, settings)
                .then<void>(
                  (_) => fail('must timeout'),
                  onError: (Object e) {
                    outcome = e;
                  },
                ),
          );
          clock.flushMicrotasks();
          expect(calls, 1);
          clock.elapse(const Duration(seconds: 59));
          expect(outcome, isNull);
          clock.elapse(const Duration(seconds: 1));
          expect(outcome, safe('Speech request timed out.'));
          if (error) {
            release.completeError(http.ClientException('private-key'));
          } else {
            release.complete(http.Response.bytes([1, 2], 200));
          }
          clock.flushMicrotasks();
          expect(calls, 1);
          expect(outcome, safe('Speech request timed out.'));
        });
      },
    );
  }
  test(
    'timeout seam positive and privacy refusal remains before send',
    () async {
      expect(() => SpeechService(timeout: Duration.zero), throwsArgumentError);
      expect(
        () => SpeechService(timeout: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      PrivacyGuard.debugLocalOnlyOverride = true;
      var calls = 0;
      final s = SpeechService(
        client: MockClient((_) async {
          calls++;
          return http.Response.bytes([1], 200);
        }),
      );
      await expectLater(
        s.synthesize(
          input,
          const BrainSettings(
            backend: BrainBackend.openAiCompatible,
            baseUrl: 'https://remote.invalid',
            model: 'm',
          ),
        ),
        throwsA(
          isA<SpeechException>().having(
            (e) => e.message,
            'refusal',
            contains('Local-only mode'),
          ),
        ),
      );
      expect(calls, 0);
    },
  );
}
