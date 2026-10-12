import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/line_connection.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/link/phone_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('routing fixture timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in ['paired-first', 'unpaired-first', 'disconnected']) {
    test('actual reply routes only exact live paired origin $scenario', () async {
      const key = 'fabricated-routing-key';
      SharedPreferences.setMockInitialValues({'link.key': key});
      final server = PhoneServer();
      addTearDown(server.stop);
      await server.start(advertise: false);
      final seen = <List<Packet>>[];
      final clients = <LineConnection>[];
      final commands = <Packet>[];
      server.requests.listen(commands.add);
      for (var index = 0; index < 2; index++) {
        final client = LineConnection(
          await Socket.connect(InternetAddress.loopbackIPv4, server.port),
        )..start();
        clients.add(client);
        addTearDown(client.close);
        final packets = <Packet>[];
        seen.add(packets);
        client.packets.listen(packets.add);
        client.send(Packet(hello: 'Fabricated$index'));
        await until(() => packets.any((p) => p.command == 'authRequired'));
        if (!(scenario == 'unpaired-first' && index == 0)) {
          final nonce = packets
              .firstWhere((p) => p.command == 'authRequired')
              .text!;
          client.send(
            Packet(
              command: 'auth',
              text: Hmac(
                sha256,
                utf8.encode(key),
              ).convert(utf8.encode(nonce)).toString(),
            ),
          );
          await until(() => packets.any((p) => p.command == 'paired'));
        }
      }
      clients.last.send(Packet(command: 'wake', callID: 'same-fabricated-id'));
      await until(() => commands.length == 1);
      final request = commands.single;
      if (scenario == 'disconnected') {
        await clients.last.close();
        await until(() => server.phoneNames.length == 1);
      }
      // A lookalike packet is not the delivered request object.
      server.reply(
        Packet(command: 'wake', callID: request.callID),
        Packet(command: 'reply', text: 'unknown'),
      );
      server.reply(request, Packet(command: 'reply', text: 'origin-only'));
      if (scenario != 'disconnected') {
        await until(() => seen.last.any((p) => p.text == 'origin-only'));
        expect(seen.last.where((p) => p.command == 'reply'), hasLength(1));
      }
      // Flush a later authenticated request through the remaining live client.
      final barrierClient = scenario == 'disconnected'
          ? clients.first
          : clients.last;
      barrierClient.send(Packet(command: 'wake', callID: 'barrier'));
      await until(() => commands.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.first.where((p) => p.command == 'reply'), isEmpty);
      expect(seen.expand((p) => p).where((p) => p.text == 'unknown'), isEmpty);
      if (scenario == 'disconnected') {
        expect(
          seen.expand((p) => p).where((p) => p.command == 'reply'),
          isEmpty,
        );
      }
    });
  }
}
