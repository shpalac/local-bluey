import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/ollama_provider.dart';
import 'package:local_bluey/llm/openai_compatible_provider.dart';
import 'package:local_bluey/llm/retry.dart';

class ScriptClient extends http.BaseClient {
  ScriptClient(this.action);
  final Future<http.StreamedResponse> Function(int) action;
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      action(++calls);
}

http.StreamedResponse response(bool open, {int status = 200, String? body}) =>
    http.StreamedResponse(
      Stream.value(
        utf8.encode(
          body ??
              jsonEncode(
                open
                    ? {
                        'choices': [
                          {
                            'message': {'content': 'ok'},
                          },
                        ],
                      }
                    : {
                        'message': {'content': 'ok'},
                      },
              ),
        ),
      ),
      status,
    );
Future<String> run(bool open, bool tools, http.Client client) async {
  final LlmProvider p = open
      ? OpenAiCompatibleProvider(
          baseUrl: 'http://synthetic.invalid',
          model: 'fake',
          client: client,
        )
      : OllamaProvider(baseUrl: 'http://synthetic.invalid', client: client);
  return tools ? (await p.chatWithTools([])).text : await p.chat([]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final open in [false, true]) {
    for (final tools in [false, true]) {
      final label = '${open ? "OpenAI" : "Ollama"} ${tools ? "tools" : "text"}';
      for (final status in [401, 403, 404, 429, 500]) {
        test('$label permanent HTTP $status exactly one request', () async {
          final client = ScriptClient(
            (_) async => response(open, status: status, body: 'permanent'),
          );
          await expectLater(
            run(open, tools, client),
            throwsA(isA<LlmException>()),
          );
          expect(client.calls, 1);
        });
      }
      for (final body in ['not json', '[]', '{"message":42,"choices":42}']) {
        test('$label invalid response exactly one request $body', () async {
          final client = ScriptClient((_) async => response(open, body: body));
          await expectLater(run(open, tools, client), throwsA(anything));
          expect(client.calls, 1);
        });
      }
      for (final timeout in [false, true]) {
        test(
          '$label typed ${timeout ? "timeout" : "socket"} exact exponential delay then success',
          () {
            fakeAsync((async) {
              final client = ScriptClient((n) async {
                if (n < 3) {
                  if (timeout) throw TimeoutException('synthetic');
                  throw const SocketException('synthetic');
                }
                return response(open);
              });
              String? result;
              Object? error;
              run(open, tools, client).then(
                (v) => result = v,
                onError: (Object e) {
                  error = e;
                },
              );
              async.flushMicrotasks();
              expect(client.calls, 1);
              expect(result, isNull);
              async.elapse(const Duration(milliseconds: 299));
              async.flushMicrotasks();
              expect(client.calls, 1);
              async.elapse(const Duration(milliseconds: 1));
              async.flushMicrotasks();
              expect(client.calls, 2);
              async.elapse(const Duration(milliseconds: 599));
              async.flushMicrotasks();
              expect(client.calls, 2);
              async.elapse(const Duration(milliseconds: 1));
              async.flushMicrotasks();
              expect(client.calls, 3);
              expect(result, 'ok');
              expect(error, isNull);
            });
          },
        );
      }
      test(
        '$label generic client error not inferred from transport sounding text',
        () async {
          final client = ScriptClient(
            (_) async => throw http.ClientException('socket timeout 503 retry'),
          );
          await expectLater(
            run(open, tools, client),
            throwsA(isA<http.ClientException>()),
          );
          expect(client.calls, 1);
        },
      );
    }
  }
  test('default permanent errors no callback, explicit predicate replaces classification', () async {
    var calls = 0, callbacks = 0;
    await expectLater(
      withRetry(() async {
        calls++;
        throw ArgumentError('bad');
      }, onRetry: (_, _) => callbacks++),
      throwsArgumentError,
    );
    expect(calls, 1);
    expect(callbacks, 0);
    calls = 0;
    final result = await withRetry(
      () async {
        calls++;
        if (calls < 2) throw ArgumentError('explicit');
        return 'ok';
      },
      initialDelay: Duration.zero,
      shouldRetry: (_) => true,
      onRetry: (_, _) => callbacks++,
    );
    expect(result, 'ok');
    expect(calls, 2);
    expect(callbacks, 1);
  });
  test('predicate/callback errors propagate no subsequent call; final attempt skips predicate', () async {
    for (final callback in [false, true]) {
      var calls = 0;
      await expectLater(
        withRetry(
          () async {
            calls++;
            throw const SocketException('x');
          },
          shouldRetry: (_) {
            if (!callback) throw StateError('predicate');
            return true;
          },
          onRetry: (_, _) => throw StateError('callback'),
        ),
        throwsStateError,
      );
      expect(calls, 1);
    }
    var predicates = 0;
    await expectLater(
      withRetry(
        () async => throw const SocketException('final'),
        maxAttempts: 1,
        shouldRetry: (_) {
          predicates++;
          return true;
        },
      ),
      throwsA(isA<SocketException>()),
    );
    expect(predicates, 0);
  });
  test('invalid attempts/delays never invoke call', () async {
    var calls = 0;
    Future<int> invoke() async => ++calls;
    for (final n in [0, -1, 11]) {
      await expectLater(withRetry(invoke, maxAttempts: n), throwsArgumentError);
    }
    for (final d in [
      const Duration(microseconds: -1),
      const Duration(seconds: 61),
    ]) {
      await expectLater(
        withRetry(invoke, initialDelay: d),
        throwsArgumentError,
      );
    }
    expect(calls, 0);
  });
  test('exhaustion attempt/callback bound and delay cap', () {
    fakeAsync((async) {
      var calls = 0;
      final callbacks = <int>[];
      Object? error;
      withRetry(
        () async {
          calls++;
          throw const SocketException('down');
        },
        maxAttempts: 4,
        initialDelay: const Duration(seconds: 40),
        onRetry: (n, _) => callbacks.add(n),
      ).then(
        (_) {},
        onError: (Object e) {
          error = e;
        },
      );
      async.flushMicrotasks();
      expect(calls, 1);
      async.elapse(const Duration(seconds: 40));
      async.flushMicrotasks();
      expect(calls, 2);
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(calls, 3);
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(calls, 4);
      expect(callbacks, [1, 2, 3]);
      expect(error, isA<SocketException>());
      expect(async.nonPeriodicTimerCount, 0);
    });
  });
}
