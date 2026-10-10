import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_bluey/services/endpoint_assistant.dart';
import 'package:local_bluey/services/settings_store.dart';

void main() {
  for (final backend in BrainBackend.values) {
    final field = backend == BrainBackend.ollama ? 'models' : 'data';
    final id = backend == BrainBackend.ollama ? 'name' : 'id';
    final invalid = <String, Object?>{
      'empty object': {},
      'null': null,
      'array': [],
      'scalar': 42,
      'missing': {'other': []},
      'null field': {field: null},
      'wrong list': {field: {}},
      'null row': {
        field: [null],
      },
      'wrong row': {
        field: ['private'],
      },
      'missing id': {
        field: [{}],
      },
      'null id': {
        field: [
          {id: null},
        ],
      },
      'wrong id': {
        field: [
          {id: 7},
        ],
      },
      'empty id': {
        field: [
          {id: ''},
        ],
      },
      'blank id': {
        field: [
          {id: ' \n\t '},
        ],
      },
      'partial malformed': {
        field: [
          {id: 'valid'},
          {id: ''},
        ],
      },
    };
    for (final entry in invalid.entries) {
      test(
        '$backend ${entry.key} is badResponse not false verification',
        () async {
          final a = EndpointAssistant(
            client: MockClient(
              (_) async => http.Response(jsonEncode(entry.value), 200),
            ),
          );
          final result = await a.checkEndpoint(
            baseUrl: 'http://localhost:11434',
            backend: backend,
          );
          expect(result, isA<EndpointCheckFailed>());
          expect(
            (result as EndpointCheckFailed).reason,
            EndpointCheckFailure.badResponse,
          );
          expect(result.detail, 'Invalid model-list response.');
        },
      );
    }
    for (final empty in [false, true]) {
      test(
        '$backend explicit ${empty ? 'empty' : 'valid metadata'} accepted readonly original IDs',
        () async {
          final ids = empty ? <String>[] : [' space-preserved:latest ', 'שלום'];
          final body = {
            field: [
              for (final v in ids)
                {
                  id: v,
                  'metadata': {'extra': true},
                },
            ],
            'extra': 'allowed',
          };
          final a = EndpointAssistant(
            client: MockClient((req) async {
              expect(
                req.url.path,
                backend == BrainBackend.ollama ? '/api/tags' : '/models',
              );
              expect(req.headers['Authorization'], 'Bearer key');
              return http.Response(
                jsonEncode(body),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          );
          final result = await a.checkEndpoint(
            baseUrl: 'http://localhost:11434',
            backend: backend,
            apiKey: 'key',
          );
          expect(result, isA<EndpointCheckOk>());
          final models = (result as EndpointCheckOk).models;
          expect(models, ids);
          expect(() => models.add('new'), throwsUnsupportedError);
          if (models.isNotEmpty) {
            expect(() => models[0] = 'changed', throwsUnsupportedError);
          }
          ids.clear();
          expect(models.length, empty ? 0 : 2);
        },
      );
    }
    for (final failure in ['http', 'transport', 'parse']) {
      test(
        '$backend $failure drops private sentinels preserves typed category/status',
        () async {
          const sentinel = 'secret-key /private/path http://private.invalid';
          final a = EndpointAssistant(
            client: MockClient((_) async {
              if (failure == 'transport') throw http.ClientException(sentinel);
              return http.Response(sentinel, failure == 'http' ? 401 : 200);
            }),
          );
          final result = await a.checkEndpoint(
            baseUrl: 'http://localhost:11434',
            backend: backend,
          ) as EndpointCheckFailed;
          expect(
            result.reason,
            failure == 'http'
                ? EndpointCheckFailure.httpError
                : failure == 'transport'
                ? EndpointCheckFailure.unreachable
                : EndpointCheckFailure.badResponse,
          );
          expect(result.statusCode, failure == 'http' ? 401 : null);
          expect(result.detail, isNot(contains('secret-key')));
          expect(result.detail, isNot(contains('/private/path')));
          expect(result.detail, isNot(contains('private.invalid')));
          expect(result.detail!.length, lessThan(80));
        },
      );
    }
  }
  for (final body in [
    '{}',
    '{"models":null}',
    '{"models":[]}',
    '{"models":[{"name":"first"},{"name":"second"}]}',
  ]) {
    test(
      'actual detection validates $body and readonly suggested model',
      () async {
        final a = EndpointAssistant(
          client: MockClient((_) async => http.Response(body, 200)),
        );
        final d = await a.detectLocalOllama();
        if (body == '{}' || body.contains('null')) {
          expect(d, isNull);
        } else {
          expect(d, isNotNull);
          expect(d!.suggestedModel, body.contains('first') ? 'first' : null);
          expect(() => d.models.add('new'), throwsUnsupportedError);
        }
      },
    );
  }
}
