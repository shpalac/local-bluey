import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/ollama_provider.dart';
import 'package:local_bluey/llm/openai_compatible_provider.dart';
import 'package:local_bluey/llm/stream_records.dart';

class BodyClient extends http.BaseClient {
  BodyClient(this.body, {this.status = 200});
  final Stream<List<int>> body;
  final int status;
  bool closed = false;
  http.BaseRequest? request;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    return http.StreamedResponse(body, status);
  }

  @override
  void close() {
    closed = true;
  }
}

LlmProvider provider(bool sse, http.Client client) => sse
    ? OpenAiCompatibleProvider(
        baseUrl: 'http://synthetic.invalid/v1',
        model: 'fake',
        apiKey: 'synthetic-token',
        client: client,
      )
    : OllamaProvider(
        baseUrl: 'http://synthetic.invalid',
        model: 'fake',
        client: client,
      );
String record(bool sse, String content) => sse
    ? 'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': content},
          },
        ],
      })}\n\n'
    : '${jsonEncode({
        'message': {'content': content},
      })}\n';
Future<String> answer(bool sse, List<List<int>> chunks) async {
  final client = BodyClient(Stream.fromIterable(chunks));
  final result = (await provider(
    sse,
    client,
  ).chatStream([LlmMessage('user', 'fixture')]).toList()).join();
  expect(client.closed, isFalse);
  return result;
}

void main() {
  for (final sse in [false, true]) {
    test(
      '${sse ? "SSE" : "NDJSON"} every byte split including Hebrew preserves exact tokens',
      () async {
        final bytes = utf8.encode(record(sse, 'שלום') + record(sse, ' world'));
        for (var split = 1; split < bytes.length; split++) {
          expect(
            await answer(sse, [bytes.sublist(0, split), bytes.sublist(split)]),
            'שלום world',
          );
        }
        expect(await answer(sse, bytes.map((b) => [b]).toList()), 'שלום world');
      },
    );
    test(
      '${sse ? "SSE" : "NDJSON"} CRLF multiple records metadata empty and final EOF',
      () async {
        final metadata = sse
            ? ': comment\r\nevent: message\r\nid: 7\r\n\r\ndata: {"choices":[]}\r\n\r\n'
            : '{"model":"fake"}\r\n';
        final text =
            metadata +
            record(sse, '').replaceAll('\n', '\r\n') +
            record(sse, 'a').replaceAll('\n', '\r\n') +
            record(sse, 'ב').trimRight();
        expect(await answer(sse, [utf8.encode(text)]), 'aב');
      },
    );
    for (final bad in [
      '{bad',
      '{"error":{"message":"secret raw"}}',
      '{"message":{"content":42},"choices":[{"delta":{"content":42}}]}',
      '[1]',
    ]) {
      test(
        '${sse ? "SSE" : "NDJSON"} malformed/structured errors honest without raw echo $bad',
        () async {
          final client = BodyClient(
            Stream.value(utf8.encode(sse ? 'data: $bad\n\n' : '$bad\n')),
          );
          await expectLater(
            provider(sse, client).chatStream([]).toList(),
            throwsA(predicate((e) => !e.toString().contains('secret raw'))),
          );
          expect(client.closed, isFalse);
        },
      );
    }
    test('${sse ? "SSE" : "NDJSON"} invalid utf8 errors', () async {
      await expectLater(
        answer(sse, [
          [0xff, 10],
        ]),
        throwsFormatException,
      );
    });
    test(
      '${sse ? "SSE" : "NDJSON"} oversized pending line fails before later data',
      () async {
        final client = BodyClient(
          Stream.value(List.filled(maxStreamRecordBytes + 1, 65)),
        );
        await expectLater(
          provider(sse, client).chatStream([]).toList(),
          throwsFormatException,
        );
        expect(client.closed, isFalse);
      },
    );
    test(
      '${sse ? "SSE" : "NDJSON"} non200 owns body cancellation/shared client remains',
      () async {
        var cancelled = 0;
        final body = StreamController<List<int>>(onCancel: () => cancelled++);
        final client = BodyClient(body.stream, status: 503);
        await expectLater(
          provider(sse, client).chatStream([]).toList(),
          throwsA(isA<LlmException>()),
        );
        expect(cancelled, 1);
        expect(client.closed, isFalse);
        await body.close();
      },
    );
    test(
      '${sse ? "SSE" : "NDJSON"} body error consumes failure and releases listener',
      () async {
        var cancelled = 0;
        final body = StreamController<List<int>>(onCancel: () => cancelled++);
        final client = BodyClient(body.stream);
        final result = provider(sse, client).chatStream([]).toList();
        final expected = expectLater(result, throwsStateError);
        await Future<void>.delayed(Duration.zero);
        body.addError(StateError('synthetic'));
        await body.close();
        await expected;
        expect(cancelled, 1);
        expect(client.closed, isFalse);
      },
    );
    test(
      '${sse ? "SSE" : "NDJSON"} entered body subscriber cancellation releases consumption',
      () async {
        final entered = Completer<void>();
        var cancelled = 0;
        final body = StreamController<List<int>>(
          onListen: () => entered.complete(),
          onCancel: () => cancelled++,
        );
        final client = BodyClient(body.stream);
        final tokens = <String>[];
        final token = Completer<void>();
        final sub = provider(sse, client).chatStream([]).listen((v) {
          tokens.add(v);
          token.complete();
        });
        await entered.future;
        body.add(utf8.encode(record(sse, 'token')));
        await token.future;
        await sub.cancel();
        expect(cancelled, 1);
        expect(tokens, ['token']);
        expect(client.closed, isFalse);
        await body.close();
      },
    );
    test(
      '${sse ? "SSE" : "NDJSON"} terminal marker ignores trailing malformed data and cancels body',
      () async {
        var cancelled = 0;
        final body = StreamController<List<int>>(onCancel: () => cancelled++);
        final client = BodyClient(body.stream);
        final result = provider(sse, client).chatStream([]).toList();
        await Future<void>.delayed(Duration.zero);
        body.add(
          utf8.encode(
            '${record(sse, 'a')}${sse ? 'data: [DONE]\n\n' : '{"done":true}\n'}bad\n',
          ),
        );
        expect(await result, ['a']);
        expect(cancelled, 1);
        expect(client.closed, isFalse);
        await body.close();
      },
    );
  }
  test('SSE multiline data field forms one complete JSON event', () async {
    expect(
      await answer(true, [
        utf8.encode(
          'data: {"choices":\ndata: [{"delta":{"content":"joined"}}]}\n\n',
        ),
      ]),
      'joined',
    );
  });
  test(
    'SSE accumulated event cap catches many individually small lines',
    () async {
      final lines = List.filled(100, 'data: ${'a' * 1000}\n').join();
      await expectLater(
        answer(true, [utf8.encode(lines)]),
        throwsFormatException,
      );
    },
  );
  for (final sse in [false, true]) {
    test(
      '${sse ? "SSE" : "NDJSON"} malformed record cancels active owned body',
      () async {
        var cancelled = 0;
        final entered = Completer<void>();
        final body = StreamController<List<int>>(
          onListen: () => entered.complete(),
          onCancel: () => cancelled++,
        );
        final client = BodyClient(body.stream);
        final result = provider(sse, client).chatStream([]).toList();
        final expected = expectLater(result, throwsFormatException);
        await entered.future;
        body.add(utf8.encode(sse ? 'data: {truncated\n\n' : '{truncated\n'));
        await expected;
        expect(cancelled, 1);
        expect(client.closed, isFalse);
        await body.close();
      },
    );
    test(
      '${sse ? "SSE" : "NDJSON"} exact line cap accepted and no streaming tool dispatch',
      () async {
        final json = jsonEncode({'unknown': 'x'});
        final prefix = sse ? 'data: ' : '';
        final line =
            prefix + json.padRight(maxStreamRecordBytes - prefix.length);
        expect(
          await answer(sse, [utf8.encode('$line\n${sse ? "\n" : ""}')]),
          '',
        );
        final tool = sse
            ? {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'function': {'name': 'click'},
                        },
                      ],
                    },
                  },
                ],
              }
            : {
                'message': {
                  'tool_calls': [
                    {
                      'function': {'name': 'click'},
                    },
                  ],
                },
              };
        expect(
          await answer(sse, [
            utf8.encode(
              sse ? 'data: ${jsonEncode(tool)}\n\n' : '${jsonEncode(tool)}\n',
            ),
          ]),
          '',
        );
      },
    );
  }
}
