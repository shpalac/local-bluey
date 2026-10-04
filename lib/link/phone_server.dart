import 'dart:async';
import 'dart:io';

import 'package:nsd/nsd.dart' as nsd;

import 'line_connection.dart';
import 'models.dart';

/// The Bonjour service type both sides agree on (was GooglyService.type).
const String kServiceType = '_googly._tcp';

/// Advertises the Mac on the local network and streams face updates to any phone
/// that connects, ported from Mac/PhoneServer.swift.
class PhoneServer {
  final _phones = <LineConnection, String?>{};
  FaceState? _lastSent;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  ServerSocket? _server;
  nsd.Registration? _registration;

  final _onPhonesChanged = StreamController<List<String>>.broadcast();
  Stream<List<String>> get phonesChanged => _onPhonesChanged.stream;
  List<String> get phoneNames =>
      _phones.values.map((n) => n ?? 'iPhone').toList();

  /// Packets carrying a command from a phone.
  final _requests = StreamController<Packet>.broadcast();
  Stream<Packet> get requests => _requests.stream;

  /// Replies to the phone that sent [request].
  void reply(Packet request, Packet response) {
    for (final entry in _phones.entries) {
      // Replies ride the same connection; keyed by callID when present.
      entry.key.send(response);
      break; // single-phone use today; extend with per-connection routing later
    }
  }

  Future<void> start({int port = 0}) async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server!.listen((socket) {
      final link = LineConnection(socket)..start();
      _phones[link] = null;
      link.send(Packet(hello: Platform.localHostname));
      if (_lastSent != null) link.send(Packet(face: _lastSent));
      _onPhonesChanged.add(phoneNames);
      link.packets.listen((packet) {
        if (packet.hello != null) {
          _phones[link] = packet.hello;
          _onPhonesChanged.add(phoneNames);
        }
        if (packet.command != null) _requests.add(packet);
      });
      link.done.listen((_) {
        _phones.remove(link);
        _onPhonesChanged.add(phoneNames);
      });
    });

    _registration = await nsd.register(
      nsd.Service(
        name: Platform.localHostname,
        type: kServiceType,
        port: _server!.port,
      ),
    );
  }

  /// Sends a packet to every phone (e.g. "wake", "sleep").
  void broadcast(Packet packet) {
    for (final link in _phones.keys) {
      link.send(packet);
    }
  }

  /// Sends the face to every phone, skipping updates too small to see.
  void sendFace(FaceState face) {
    final now = DateTime.now();
    final last = _lastSent;
    if (last != null && now.difference(_lastSentAt).inSeconds < 1) {
      final same =
          last.mood == face.mood &&
          (last.gazeX - face.gazeX).abs() < 0.004 &&
          (last.gazeY - face.gazeY).abs() < 0.004 &&
          (last.talk - face.talk).abs() < 0.02;
      if (same) return;
    }
    _lastSent = face;
    _lastSentAt = now;
    broadcast(Packet(face: face));
  }

  Future<void> stop() async {
    if (_registration != null) await nsd.unregister(_registration!);
    await _server?.close();
    for (final link in _phones.keys) {
      await link.close();
    }
    _phones.clear();
  }
}
