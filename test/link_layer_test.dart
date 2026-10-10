import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/line_connection.dart';
import 'package:local_bluey/link/models.dart';

/// Loopback socket pair, no platform channels involved.
Future<(LineConnection, LineConnection)> _pair() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final serverLink = Completer<LineConnection>();
  server.listen((s) => serverLink.complete(LineConnection(s)..start()));
  final client = LineConnection(
    await Socket.connect(InternetAddress.loopbackIPv4, server.port),
  )..start();
  final other = await serverLink.future;
  addTearDown(server.close);
  return (client, other);
}

void main() {
  group('LineConnection framing (#115)', () {
    test('delivers multiple packets from one chunk', () async {
      final (a, b) = await _pair();
      final received = <Packet>[];
      b.packets.listen(received.add);
      a.send(Packet(command: 'one'));
      a.send(Packet(command: 'two'));
      a.send(Packet(command: 'three'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(received.map((p) => p.command), ['one', 'two', 'three']);
      await a.close();
      await b.close();
    });

    test('delivers a large multi-chunk frame intact', () async {
      final (a, b) = await _pair();
      final received = <Packet>[];
      b.packets.listen(received.add);
      final big = 'a' * (3 * 1024 * 1024); // 3MB, base64-audio scale
      a.send(Packet(command: 'audio', text: big));
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(received, hasLength(1));
      expect(received.single.text, big);
      await a.close();
      await b.close();
    });

    test('drops the connection past the byte limit', () async {
      final (a, b) = await _pair();
      final done = Completer<void>();
      b.done.listen((_) => done.complete());
      // One single frame larger than the limit, not many small ones.
      final huge = 'x' * (20 * 1024 * 1024);
      a.send(Packet(command: 'x', text: huge));
      await done.future.timeout(const Duration(seconds: 10));
      expect(b.isClosed, isTrue);
      await a.close();
    });
  });

  group('LineConnection close semantics (#113)', () {
    test(
      'terminal authFailed sent before close reaches loopback peer',
      () async {
        final (a, b) = await _pair();
        final terminal = b.packets.first;
        a.send(Packet(command: 'authFailed'));
        await a.close();
        expect(
          (await terminal.timeout(const Duration(seconds: 3))).command,
          'authFailed',
        );
        await b.close();
      },
    );
    test('local close emits done exactly once', () async {
      final (a, b) = await _pair();
      var count = 0;
      b.done.listen((_) => count++);
      await b.close();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(count, 1);
      expect(b.isClosed, isTrue);
      await a.close();
    });

    test('remote close still emits done', () async {
      final (a, b) = await _pair();
      final done = Completer<void>();
      b.done.listen((_) => done.complete());
      await a.close();
      await done.future.timeout(const Duration(seconds: 2));
      await b.close();
    });

    test('send after close is a no-op, not a throw (#110/#113)', () async {
      final (a, b) = await _pair();
      await a.close();
      a.send(Packet(command: 'late'));
      await b.close();
    });

    test('close is idempotent', () async {
      final (a, b) = await _pair();
      await a.close();
      await a.close();
      await b.close();
    });
  });

  group('HMAC challenge-response (#111)', () {
    String answer(String key, String nonce) =>
        Hmac(sha256, utf8.encode(key)).convert(utf8.encode(nonce)).toString();

    test('both sides derive the same answer from (key, nonce)', () {
      expect(answer('key1', 'nonce1'), answer('key1', 'nonce1'));
      expect(answer('key1', 'nonce1'), isNot('key1'));
    });

    test('wrong key or wrong nonce fails', () {
      expect(answer('key1', 'nonce1'), isNot(answer('key2', 'nonce1')));
      expect(answer('key1', 'nonce1'), isNot(answer('key1', 'nonce2')));
    });
  });
}
