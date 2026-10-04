import 'dart:async';
import 'dart:io';

import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart';

import 'line_connection.dart';
import 'models.dart';
import 'phone_server.dart' show kServiceType;

/// iOS side of the link: discovers the Mac over Bonjour (nsd) and keeps one
/// LineConnection to it, ported from iOS/MacLink.swift.
class DiscoveredMac {
  const DiscoveredMac(this.name, this.host, this.port);

  final String name;
  final String host;
  final int port;
}

class MacLink {
  MacLink({this.deviceName = 'iPhone'});

  final String deviceName;

  final _faces = StreamController<FaceState>.broadcast();
  final _packets = StreamController<Packet>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final _macs = StreamController<List<DiscoveredMac>>.broadcast();

  /// Manually chosen Mac name; when set, only that Mac is connected.
  String? preferredMac;

  Stream<FaceState> get faces => _faces.stream;
  Stream<Packet> get packets => _packets.stream;
  Stream<bool> get connected => _connected.stream;
  Stream<List<DiscoveredMac>> get macs => _macs.stream;

  static const _kLinkKey = 'link.key';

  String? macName;
  bool get isConnected => _link != null;

  /// True once the Mac accepted this phone (paired or re-authenticated).
  final _paired = StreamController<bool>.broadcast();
  Stream<bool> get paired => _paired.stream;

  LineConnection? _link;
  nsd.Discovery? _discovery;
  Timer? _retry;

  Future<void> start() async {
    _discovery = await nsd.startDiscovery(kServiceType);
    final found = <String, DiscoveredMac>{};
    _discovery!.addServiceListener((service, status) {
      final name = service.name ?? 'Mac';
      if (status == nsd.ServiceStatus.found) {
        if (service.host != null && service.port != null) {
          found[name] = DiscoveredMac(name, service.host!, service.port!);
        }
      } else {
        found.remove(name);
      }
      _macs.add(found.values.toList());
      final candidate = preferredMac == null
          ? found.values.firstOrNull
          : found[preferredMac];
      if (_link == null && candidate != null) {
        _connect(candidate.host, candidate.port);
      }
    });
  }

  Future<void> _connect(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      final link = LineConnection(socket)..start();
      _link = link;
      link.send(Packet(hello: deviceName));
      _connected.add(true);
      link.packets.listen((packet) async {
        if (packet.hello != null) macName = packet.hello;
        switch (packet.command) {
          case 'authRequired':
            final key = (await SharedPreferences.getInstance())
                .getString(_kLinkKey);
            if (key != null) {
              link.send(Packet(command: 'auth', text: key));
            }
            return;
          case 'paired':
            if (packet.text != null) {
              await (await SharedPreferences.getInstance())
                  .setString(_kLinkKey, packet.text!);
            }
            _paired.add(true);
            return;
          case 'authFailed':
            await (await SharedPreferences.getInstance()).remove(_kLinkKey);
            _paired.add(false);
            return;
        }
        if (packet.face != null) _faces.add(packet.face!);
        _packets.add(packet);
      });
      link.done.listen((_) => _drop());
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _drop() {
    _link = null;
    macName = null;
    _connected.add(false);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 3), () async {
      if (_discovery != null) await nsd.stopDiscovery(_discovery!);
      await start();
    });
  }

  void send(Packet packet) => _link?.send(packet);

  /// Connects to a specific Mac chosen by the user.
  void select(DiscoveredMac mac) {
    preferredMac = mac.name;
    if (_link == null) _connect(mac.host, mac.port);
  }

  bool _stopped = false;

  /// Idempotent shutdown.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _retry?.cancel();
    if (_discovery != null) await nsd.stopDiscovery(_discovery!);
    await _link?.close();
    _link = null;
  }
}
