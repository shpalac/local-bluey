import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_bluey/services/diagnostics.dart';
import 'package:local_bluey/services/settings_store.dart';

class Client extends http.BaseClient {
  final response = Completer<http.StreamedResponse>();
  int sends = 0;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sends++;
    expect(request.followRedirects, isFalse);
    expect(request.headers.keys, isNot(contains('authorization')));
    return response.future;
  }

  @override
  void close() {
    closed = true;
  }
}

Future<CheckResult> probe(
  Client client,
  String url, {
  bool local = true,
  Duration timeout = const Duration(seconds: 4),
}) => Diagnostics.providerReachable(
  settings: () async => BrainSettings(
    backend: BrainBackend.openAiCompatible,
    baseUrl: url,
    model: 'm',
    apiKey: 'sk-private-secret',
  ),
  localOnly: () async => local,
  client: client,
  timeout: timeout,
);
void main() {
  for (final url in [
    'https://localhost.evil.invalid',
    'https://127.0.0.1.evil.invalid',
    'https://evil.invalid/localhost',
    'https://evil.invalid?q=127.0.0.1',
    'https://localhost@evil.invalid',
    'http://device.local',
    'http://192.168.1.2',
    'http://10.0.0.1',
    'file://localhost/a',
    'ftp://localhost/a',
    'not a url',
    '',
    'http://[broken',
    'http://evil.invalid/#localhost',
  ]) {
    test('local-only refuses without send $url', () async {
      final client = Client();
      final result = await probe(client, url);
      expect(result.status, CheckStatus.fail);
      expect(client.sends, 0);
      expect(client.closed, isFalse);
      expect(
        '${result.fixEn} ${result.fixHe}',
        isNot(contains('evil.invalid')),
      );
    });
  }
  for (final url in [
    'http://localhost:9',
    'https://LOCALHOST',
    'http://127.2.3.4:9',
    'http://0.0.0.0',
    'http://[::1]:9',
    'http://[::ffff:127.0.0.1]:9',
  ]) {
    test(
      'existing supported loopback form sends and cancels body $url',
      () async {
        final client = Client();
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () {
            cancelled = true;
          },
        );
        client.response.complete(http.StreamedResponse(body.stream, 200));
        final result = await probe(client, url);
        expect(result.status, CheckStatus.pass);
        expect(result.fixEn, contains('reach'));
        expect(result.fixEn, contains('not verified'));
        expect(client.sends, 1);
        expect(cancelled, isTrue);
        expect(client.closed, isFalse);
        await body.close();
      },
    );
  }
  for (final status in [301, 302, 307, 308, 401, 403, 404, 500]) {
    test('non-success $status never pass or redirect follow', () async {
      final client = Client();
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      client.response.complete(
        http.StreamedResponse(
          body.stream,
          status,
          headers: {'location': 'https://remote.invalid/sk-secret'},
        ),
      );
      final result = await probe(client, 'http://localhost');
      expect(result.status, CheckStatus.fail);
      expect(client.sends, 1);
      expect(cancelled, isTrue);
      expect('${result.fixEn} ${result.fixHe}', isNot(contains('sk-secret')));
      await body.close();
    });
  }
  for (final error in [false, true]) {
    test(
      'entered send times out before late ${error ? 'error' : 'response'} and preserves shared client',
      () {
        fakeAsync((zone) {
          final client = Client();
          CheckResult? result;
          probe(
            client,
            'http://localhost',
            timeout: const Duration(seconds: 3),
          ).then((v) {
            result = v;
          });
          zone.flushMicrotasks();
          expect(client.sends, 1);
          zone.elapse(const Duration(milliseconds: 2999));
          expect(result, isNull);
          zone.elapse(const Duration(milliseconds: 1));
          expect(result!.status, CheckStatus.fail);
          var cancelled = false;
          final body = StreamController<List<int>>(
            onCancel: () {
              cancelled = true;
            },
          );
          if (error) {
            client.response.completeError(StateError('late'));
          } else {
            client.response.complete(http.StreamedResponse(body.stream, 200));
          }
          zone.flushMicrotasks();
          if (!error) expect(cancelled, isTrue);
          expect(result!.status, CheckStatus.fail);
          expect(client.closed, isFalse);
          body.close();
          zone.flushMicrotasks();
        });
      },
    );
  }
  test(
    'stalled body and pending/failing cancellation cannot delay header result',
    () {
      fakeAsync((zone) {
        final client = Client(), cancel = Completer<void>();
        var cancelled = false;
        CheckResult? result;
        final body = StreamController<List<int>>(
          onCancel: () {
            cancelled = true;
            return cancel.future;
          },
        );
        probe(client, 'http://localhost').then((v) {
          result = v;
        });
        zone.flushMicrotasks();
        client.response.complete(http.StreamedResponse(body.stream, 204));
        zone.flushMicrotasks();
        expect(result!.status, CheckStatus.pass);
        expect(cancelled, isTrue);
        expect(cancel.isCompleted, isFalse);
        cancel.completeError(StateError('cancel'));
        zone.flushMicrotasks();
        expect(client.closed, isFalse);
        body.close();
        zone.flushMicrotasks();
      });
    },
  );
  test('settings preparation shares deadline without late send', () {
    fakeAsync((zone) {
      final settings = Completer<BrainSettings>(), client = Client();
      CheckResult? result;
      Diagnostics.providerReachable(
        settings: () => settings.future,
        localOnly: () async => true,
        client: client,
        timeout: const Duration(seconds: 3),
      ).then((v) {
        result = v;
      });
      zone.elapse(const Duration(seconds: 3));
      expect(result!.status, CheckStatus.fail);
      settings.complete(
        const BrainSettings(
          backend: BrainBackend.openAiCompatible,
          baseUrl: 'http://localhost',
          model: 'm',
        ),
      );
      zone.flushMicrotasks();
      expect(client.sends, 0);
    });
  });
  test(
    'send failure unknown, generic guidance/report does not disclose secrets',
    () async {
      final client = Client();
      final pending = probe(
        client,
        'https://remote.invalid?token=secret',
        local: false,
      );
      await Future<void>.delayed(Duration.zero);
      client.response.completeError(
        StateError('https://secret.invalid?key=sk-private-secret'),
      );
      final result = await pending;
      expect(result.status, CheckStatus.unknown);
      final report = Diagnostics.buildReport(
        platform: 'linux',
        role: 'desktop',
        results: [result],
      );
      expect(report, contains('provider: unknown'));
      expect(report, isNot(contains('secret')));
    },
  );
  test('invalid URL refused even outside local-only', () async {
    final client = Client();
    expect(
      (await probe(client, 'file://localhost/a', local: false)).status,
      CheckStatus.fail,
    );
    expect(client.sends, 0);
  });
}
