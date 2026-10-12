import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/line_connection.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/link/phone_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Transport implements LineTransport {
  final controller = StreamController<List<int>>();
  var destroys = 0;
  @override
  Stream<List<int>> get input => controller.stream;
  @override
  void configure() {}
  @override
  void write(String line) {}
  @override
  Future<void> close() async {}
  @override
  void destroy() => destroys++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('malformed typed packets across every split do not swallow next frame', () async {
    final malformed = [
      '[]',
      'null',
      '42',
      '{',
      '{"command":4}',
      '{"hello":false}',
      '{"speech":1.5}',
      '{"face":[]}',
      '{"face":{"mood":3}}',
      '{"volume":-0.01}',
      '{"volume":1.01}',
      '{"face":{"gazeX":2}}',
    ];
    for (final bad in malformed) {
      final bytes = utf8.encode(
        '$bad\n${jsonEncode(Packet(command: 'wake', text: 'בדיקה').toJson())}\n',
      );
      for (var split = 1; split < bytes.length; split++) {
        final t = _Transport();
        // One owned transport per actual connection, no network or auth.
        final actual = LineConnection.withTransport(t);
        final received = <Packet>[];
        final subscription = actual.packets.listen(received.add);
        actual.start();
        t.controller.add(bytes.sublist(0, split));
        t.controller.add(bytes.sublist(split));
        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(1), reason: '$bad split $split');
        expect(received.single.command, 'wake');
        expect(received.single.text, 'בדיקה');
        expect(actual.isClosed, isFalse);
        await actual.close();
        await subscription.cancel();
        await t.controller.close();
        expect(t.destroys, 1);
      }
    }
  });
  test('closed incomplete frame cannot complete in a new connection', () async {
    final old = _Transport(), fresh = _Transport();
    final first = LineConnection.withTransport(old),
        second = LineConnection.withTransport(fresh);
    final received = <Packet>[];
    first.start();
    old.controller.add(utf8.encode('{"command":'));
    await Future<void>.delayed(Duration.zero);
    await first.close();
    second.packets.listen(received.add);
    second.start();
    fresh.controller.add(utf8.encode('"wake"}\n{"command":"sleep"}\n'));
    await Future<void>.delayed(Duration.zero);
    expect(received.map((p) => p.command), ['sleep']);
    await second.close();
    await old.controller.close();
    await fresh.controller.close();
  });
  test('old challenge answer rejected, refreshed answer pairs, tool command dropped', () async {
    const key = 'fabricated-test-key';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('link.key', key);
    final server = PhoneServer();
    addTearDown(server.stop);
    await server.start(advertise: false);
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
    );
    final client = LineConnection(socket)..start();
    addTearDown(client.close);
    final packets = <Packet>[];
    client.packets.listen(packets.add);
    final requests = <Packet>[];
    server.requests.listen(requests.add);
    Future<Packet> next(String command) => client.packets
        .firstWhere((p) => p.command == command)
        .timeout(const Duration(seconds: 5));
    String answer(String nonce) =>
        Hmac(sha256, utf8.encode(key)).convert(utf8.encode(nonce)).toString();
    final initial = next('authRequired');
    client.send(Packet(hello: 'SyntheticPhone'));
    final oldNonce = (await initial).text!;
    final refreshed = next('authRequired');
    client.send(Packet(command: 'auth', text: 'fabricated-wrong-answer'));
    final freshNonce = (await refreshed).text!;
    expect(freshNonce, isNot(oldNonce));
    final rejected = next('authFailed'), renewed = next('authRequired');
    client.send(Packet(command: 'auth', text: answer(oldNonce)));
    await rejected;
    final currentNonce = (await renewed).text!;
    expect(packets.where((p) => p.command == 'paired'), isEmpty);
    expect(requests, isEmpty);
    final paired = next('paired');
    client.send(Packet(command: 'auth', text: answer(currentNonce)));
    await paired;
    final allowed = server.requests
        .firstWhere((p) => p.command == 'wake')
        .timeout(const Duration(seconds: 5));
    client.send(Packet(command: 'tool', tool: 'type', text: 'fabricated'));
    client.send(Packet(command: 'wake'));
    await allowed;
    expect(requests.map((p) => p.command), ['wake']);
    await client.close();
  });
}
