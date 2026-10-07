import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/line_connection.dart';
import 'package:local_bluey/link/mac_link.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/link/phone_server.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_bluey/services/speak_receipts.dart';

Future<(LineConnection, Socket)> _client(int port) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  return (LineConnection(socket)..start(), socket);
}

/// Waits for [condition] with polling, to avoid arbitrary long delays.
Future<void> _until(
  bool Function() condition, [
  Duration timeout = const Duration(seconds: 5),
]) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'host replies only track actual authenticated phone delivery (#250)',
    () async {
      final server = PhoneServer();
      final receipts = SpeakReceipts(timeout: const Duration(milliseconds: 20));
      addTearDown(receipts.dispose);
      addTearDown(server.stop);
      final decision = Completer<bool>();
      server.onPairRequest = (_) => decision.future;
      await server.start(advertise: false);
      final local = Packet(command: 'say', text: 'local answer');
      receipts.deliver(local, 'local answer', server.broadcast);
      expect(receipts.hasPending, isFalse);
      expect(local.speech, isNull);
      final (client, _) = await _client(server.port);
      addTearDown(client.close);
      final received = <Packet>[];
      client.packets.listen(received.add);
      client.send(Packet(hello: 'UnpairedPhone'));
      await _until(() => server.phoneNames.contains('UnpairedPhone'));
      receipts.deliver(
        Packet(command: 'say', text: 'still local'),
        'still local',
        server.broadcast,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(receipts.failureLog, isEmpty);
      expect(receipts.hasPending, isFalse);
      expect(received.where((packet) => packet.command == 'say'), isEmpty);
      decision.complete(true);
      await _until(() => received.any((packet) => packet.command == 'paired'));
      final remote = Packet(command: 'say', text: 'remote answer');
      receipts.deliver(remote, 'remote answer', server.broadcast);
      expect(remote.speech, isNotNull);
      await _until(() => received.any((packet) => packet.command == 'say'));
      await client.close(); // Disconnect before ack still means remote failure.
      await _until(() => receipts.failureLog.isNotEmpty);
      expect(receipts.failureLog.single, contains('Phone delivery'));
      expect(receipts.failureLog.single, contains('remote answer'));
    },
  );

  group('PhoneServer pairing (#112/#134)', () {
    test(
      'approve: phone pairs, gets the key, can send allowed commands',
      () async {
        final server = PhoneServer();
        addTearDown(server.stop);
        server.onPairRequest = (_) async => true;
        await server.start(advertise: false);

        final (client, _) = await _client(server.port);
        addTearDown(client.close);
        final received = <Packet>[];
        client.packets.listen(received.add);
        client.send(Packet(hello: 'TestPhone'));

        await _until(() => received.any((p) => p.command == 'paired'));
        final paired = received.firstWhere((p) => p.command == 'paired');
        expect(paired.text, isNotNull); // the one-time key handoff
        expect(server.phoneNames, contains('TestPhone'));

        // Paired phone can send allowlisted commands.
        final commands = <Packet>[];
        server.requests.listen(commands.add);
        client.send(Packet(command: 'wake'));
        await _until(() => commands.isNotEmpty);
        expect(commands.single.command, 'wake');
      },
    );

    test('deny: connection closed, nothing stored', () async {
      final server = PhoneServer();
      addTearDown(server.stop);
      server.onPairRequest = (_) async => false;
      await server.start(advertise: false);

      final (client, _) = await _client(server.port);
      final done = Completer<void>();
      client.done.listen((_) => done.complete());
      client.send(Packet(hello: 'SneakyPhone'));
      await done.future.timeout(const Duration(seconds: 5));
      expect(server.phoneNames.where((n) => n == 'SneakyPhone'), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('link.key'), isNull);
    });

    test('unpaired phone commands are dropped', () async {
      final server = PhoneServer();
      addTearDown(server.stop);
      // Block on a prompt that never resolves: the phone stays unpaired.
      server.onPairRequest = (_) => Completer<bool>().future;
      await server.start(advertise: false);

      final (client, _) = await _client(server.port);
      addTearDown(client.close);
      final commands = <Packet>[];
      server.requests.listen(commands.add);
      client.send(Packet(hello: 'TestPhone'));
      client.send(Packet(command: 'wake'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(commands, isEmpty);
    });

    test(
      'wrong HMAC answer: authFailed and disconnect after 3 tries',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('link.key', 'server-secret-key');
        final server = PhoneServer();
        addTearDown(server.stop);
        await server.start(advertise: false);

        final (client, _) = await _client(server.port);
        final received = <Packet>[];
        client.packets.listen(received.add);
        final done = Completer<void>();
        client.done.listen((_) => done.complete());
        client.send(Packet(hello: 'TestPhone'));
        await _until(() => received.any((p) => p.command == 'authRequired'));

        // Three wrong answers -> closed (#112).
        for (var i = 0; i < 3; i++) {
          client.send(Packet(command: 'auth', text: 'wrong-answer-$i'));
          if (i < 2) {
            await _until(
              () =>
                  received.where((p) => p.command == 'authRequired').length >
                  i + 1,
            );
          }
        }
        await done.future.timeout(const Duration(seconds: 5));
        expect(received.where((p) => p.command == 'authFailed'), hasLength(3));
        expect(received.where((p) => p.command == 'paired'), isEmpty);
      },
    );

    test('correct HMAC answer authenticates without a prompt', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('link.key', 'server-secret-key');
      final server = PhoneServer();
      addTearDown(server.stop);
      var promptCount = 0;
      server.onPairRequest = (_) async {
        promptCount++;
        return true;
      };
      await server.start(advertise: false);

      final (client, _) = await _client(server.port);
      addTearDown(client.close);
      final received = <Packet>[];
      client.packets.listen(received.add);
      client.send(Packet(hello: 'TestPhone'));
      await _until(() => received.any((p) => p.command == 'authRequired'));
      final nonce = received
          .firstWhere((p) => p.command == 'authRequired')
          .text!;
      final answer = Hmac(
        sha256,
        utf8.encode('server-secret-key'),
      ).convert(utf8.encode(nonce)).toString();
      client.send(Packet(command: 'auth', text: answer));
      await _until(() => received.any((p) => p.command == 'paired'));
      expect(promptCount, 0);
    });

    test('disconnect cleans up the phone list', () async {
      final server = PhoneServer();
      addTearDown(server.stop);
      server.onPairRequest = (_) async => true;
      await server.start(advertise: false);

      final (client, _) = await _client(server.port);
      client.send(Packet(hello: 'LeavingPhone'));
      await _until(() => server.phoneNames.contains('LeavingPhone'));
      await client.close();
      await _until(() => server.phoneNames.isEmpty);
    });

    test('disallowlisted commands are dropped even when paired', () async {
      final server = PhoneServer();
      addTearDown(server.stop);
      server.onPairRequest = (_) async => true;
      await server.start(advertise: false);

      final (client, _) = await _client(server.port);
      addTearDown(client.close);
      final received = <Packet>[];
      client.packets.listen(received.add);
      client.send(Packet(hello: 'TestPhone'));
      await _until(() => received.any((p) => p.command == 'paired'));

      final commands = <Packet>[];
      server.requests.listen(commands.add);
      client.send(Packet(command: 'rm -rf /'));
      client.send(Packet(command: 'wake'));
      await _until(() => commands.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(commands.map((p) => p.command), ['wake']);
    });
  });

  group('MacLink against a real server (#114/#134)', () {
    test('full handshake: connect, pair, reports connected', () async {
      final server = PhoneServer();
      addTearDown(server.stop);
      server.onPairRequest = (_) async => true;
      await server.start(advertise: false);

      final link = MacLink(deviceName: 'TestPhone');
      addTearDown(link.stop);
      final paired = <bool>[];
      final connected = <bool>[];
      link.paired.listen(paired.add);
      link.connected.listen(connected.add);
      await link.debugConnectTo('127.0.0.1', server.port);

      await _until(() => paired.contains(true));
      expect(connected, contains(true));
      expect(link.isConnected, isTrue);
      // The key was stored on the phone side.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('link.key'), isNotNull);
    });
  });
}
