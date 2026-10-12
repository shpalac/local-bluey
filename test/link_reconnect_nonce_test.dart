import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/line_connection.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/link/phone_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'old connection HMAC does not authenticate reconnect or forward control',
    () async {
      const key = 'fabricated-reconnect-key';
      SharedPreferences.setMockInitialValues({'link.key': key});
      final server = PhoneServer();
      addTearDown(server.stop);
      await server.start(advertise: false);
      Future<LineConnection> connect() async => LineConnection(
        await Socket.connect(InternetAddress.loopbackIPv4, server.port),
      )..start();
      Future<Packet> next(LineConnection c, String command) => c.packets
          .firstWhere((p) => p.command == command)
          .timeout(const Duration(seconds: 5));
      String answer(String nonce) =>
          Hmac(sha256, utf8.encode(key)).convert(utf8.encode(nonce)).toString();
      final old = await connect();
      addTearDown(old.close);
      final firstChallenge = next(old, 'authRequired');
      old.send(Packet(hello: 'SyntheticOld'));
      final oldNonce = (await firstChallenge).text!;
      final accepted = next(old, 'paired');
      old.send(Packet(command: 'auth', text: answer(oldNonce)));
      await accepted;
      await old.close();
      final fresh = await connect();
      addTearDown(fresh.close);
      final challenge = next(fresh, 'authRequired');
      fresh.send(Packet(hello: 'SyntheticFresh'));
      final nonce = (await challenge).text!;
      expect(nonce, isNot(oldNonce));
      final requests = <Packet>[];
      final subscription = server.requests.listen(requests.add);
      addTearDown(subscription.cancel);
      final rejected = next(fresh, 'authFailed');
      final renewed = next(fresh, 'authRequired');
      fresh.send(Packet(command: 'wake'));
      fresh.send(Packet(command: 'auth', text: answer(oldNonce)));
      await rejected;
      final current = (await renewed).text!;
      expect(requests, isEmpty);
      final paired = next(fresh, 'paired');
      fresh.send(Packet(command: 'auth', text: answer(current)));
      await paired;
      final allowed = server.requests
          .firstWhere((p) => p.command == 'wake')
          .timeout(const Duration(seconds: 5));
      fresh.send(Packet(command: 'wake'));
      await allowed;
      expect(requests.map((p) => p.command), ['wake']);
    },
  );
}
