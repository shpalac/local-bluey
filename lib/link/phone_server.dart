import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart';

import 'line_connection.dart';
import 'models.dart';

/// The Bonjour service type both sides agree on (was GooglyService.type).
const String kServiceType = '_googly._tcp';

/// Advertises the Mac on the local network and streams face updates to any phone
/// that connects, ported from Mac/PhoneServer.swift.
class PhoneServer {
  final _phones = <LineConnection, String?>{};
  final _authenticated = <LineConnection>{};
  FaceState? _lastSent;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Commands an unauthenticated phone may send.
  static const _openCommands = {'auth'};

  /// Commands a paired phone may send at all - remote control is limited to
  /// waking, sleeping and hold-to-talk. Everything else is dropped.
  static const allowedRemoteCommands = {
    'wake',
    'sleep',
    'holdStart',
    'holdEnd',
    'holdAudio',
    'playing',
    'done',
    'testVoice',
  };

  static const _kLinkKeyHash = 'link.keyHash';

  /// Asks the Mac user whether a new phone may pair. Set by the UI.
  Future<bool> Function(String deviceName)? onPairRequest;

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
      link.packets.listen((packet) async {
        if (packet.hello != null) {
          _phones[link] = packet.hello;
          _onPhonesChanged.add(phoneNames);
          await _maybePair(link, packet.hello!);
          return;
        }
        final command = packet.command;
        if (command == null) return;
        if (!_authenticated.contains(link)) {
          if (_openCommands.contains(command)) {
            await _checkAuth(link, packet.text ?? '');
          }
          // Drop everything else until paired.
          return;
        }
        if (!allowedRemoteCommands.contains(command)) return;
        _requests.add(packet);
      });
      link.done.listen((_) {
        _phones.remove(link);
        _authenticated.remove(link);
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

  /// Sends a packet to every paired phone (e.g. "wake", "sleep").
  void broadcast(Packet packet) {
    for (final link in _authenticated) {
      link.send(packet);
    }
  }

  String _hash(String key) => sha256.convert(utf8.encode(key)).toString();

  Future<String?> _storedHash() async =>
      (await SharedPreferences.getInstance()).getString(_kLinkKeyHash);

  /// First phone to connect gets a pairing prompt on the Mac; on approval the
  /// Mac generates a shared key and hands it to the phone once. Later connects
  /// must prove the key with an `auth` packet.
  Future<void> _maybePair(LineConnection link, String deviceName) async {
    final stored = await _storedHash();
    if (stored != null) {
      link.send(Packet(command: 'authRequired'));
      return;
    }
    final ask = onPairRequest;
    if (ask == null || !await ask(deviceName)) {
      link.close();
      return;
    }
    final key = _generateKey();
    await (await SharedPreferences.getInstance()).setString(
      _kLinkKeyHash,
      _hash(key),
    );
    _authenticated.add(link);
    link.send(Packet(command: 'paired', text: key));
  }

  Future<void> _checkAuth(LineConnection link, String key) async {
    final stored = await _storedHash();
    if (stored != null && _hash(key) == stored) {
      _authenticated.add(link);
      link.send(Packet(command: 'paired'));
      if (_lastSent != null) link.send(Packet(face: _lastSent));
    } else {
      link.send(Packet(command: 'authFailed'));
      link.close();
    }
  }

  static String _generateKey() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
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

  bool _stopped = false;

  /// Idempotent shutdown.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    if (_registration != null) await nsd.unregister(_registration!);
    await _server?.close();
    for (final link in _phones.keys) {
      await link.close();
    }
    _phones.clear();
  }
}
