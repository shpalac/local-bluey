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

  static const _kLinkKey = 'link.key';
  static const _kLinkKeyHash = 'link.keyHash'; // legacy, migrated on load

  /// Guards against abuse (#112): at most this many phones, per-link auth
  /// attempts before disconnect, an auth timeout, and one pairing prompt at
  /// a time so a client cannot spam dialogs.
  static const maxPhones = 8;
  static const maxAuthAttempts = 3;
  static const authTimeout = Duration(seconds: 30);

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
      if (_phones.length >= maxPhones) {
        link.close();
        return;
      }
      _phones[link] = null;
      link.send(Packet(hello: Platform.localHostname));
      // Unauthenticated links get nothing beyond the hostname (#112) and
      // are dropped if they do not authenticate in time.
      _authTimers[link] = Timer(authTimeout, () {
        if (!_authenticated.contains(link)) link.close();
      });
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
        _clearAuthState(link);
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

  /// The shared secret itself, migrated from the legacy hash-only store.
  /// Keeping the key lets the server issue nonce challenges instead of
  /// asking the phone to send the key in cleartext on every connect (#111).
  Future<String?> _storedKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_kLinkKey);
    if (key != null) return key;
    // Legacy installs only kept the hash; they must re-pair once.
    return null;
  }

  String _hmac(String key, String nonce) =>
      Hmac(sha256, utf8.encode(key)).convert(utf8.encode(nonce)).toString();

  final _authNonces = <LineConnection, String>{};
  final _authAttempts = <LineConnection, int>{};
  final _authTimers = <LineConnection, Timer>{};
  bool _pairingInFlight = false;

  /// First phone to connect gets a pairing prompt on the Mac; on approval the
  /// Mac generates a shared key and hands it to the phone once. Later
  /// connects prove the key by answering a nonce challenge (#111).
  Future<void> _maybePair(LineConnection link, String deviceName) async {
    final stored = await _storedKey();
    if (stored != null) {
      final nonce = _generateKey();
      _authNonces[link] = nonce;
      link.send(Packet(command: 'authRequired', text: nonce));
      return;
    }
    // One pairing dialog at a time; extra candidates wait or leave (#112).
    if (_pairingInFlight) {
      link.close();
      return;
    }
    final ask = onPairRequest;
    if (ask == null) {
      link.close();
      return;
    }
    _pairingInFlight = true;
    final bool approved;
    try {
      approved = await ask(deviceName);
    } finally {
      _pairingInFlight = false;
    }
    if (!approved || link.isClosed) {
      await link.close();
      return;
    }
    final key = _generateKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLinkKey, key);
    await prefs.remove(_kLinkKeyHash);
    _authenticated.add(link);
    _clearAuthState(link);
    link.send(Packet(command: 'paired', text: key));
  }

  /// Verifies an HMAC answer to the nonce challenge (#111). After
  /// [maxAuthAttempts] wrong answers the connection is dropped (#112).
  Future<void> _checkAuth(LineConnection link, String answer) async {
    final stored = await _storedKey();
    final nonce = _authNonces[link];
    if (stored != null && nonce != null && _hmac(stored, nonce) == answer) {
      _authenticated.add(link);
      _clearAuthState(link);
      link.send(Packet(command: 'paired'));
      if (_lastSent != null) link.send(Packet(face: _lastSent));
      return;
    }
    final attempts = (_authAttempts[link] ?? 0) + 1;
    _authAttempts[link] = attempts;
    link.send(Packet(command: 'authFailed'));
    if (attempts >= maxAuthAttempts) {
      await link.close();
    } else {
      // Fresh challenge for the next try.
      final next = _generateKey();
      _authNonces[link] = next;
      link.send(Packet(command: 'authRequired', text: next));
    }
  }

  void _clearAuthState(LineConnection link) {
    _authNonces.remove(link);
    _authAttempts.remove(link);
    _authTimers.remove(link)?.cancel();
  }

  /// Drops every phone and forgets the shared key - the user can re-pair
  /// from scratch (#112).
  Future<void> unpair() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLinkKey);
    await prefs.remove(_kLinkKeyHash);
    for (final link in List.of(_phones.keys)) {
      await link.close();
    }
    _phones.clear();
    _authenticated.clear();
    _onPhonesChanged.add(phoneNames);
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
