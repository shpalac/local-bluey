import 'dart:async';
import 'dart:io';

import 'package:nsd/nsd.dart' as nsd;

import 'line_connection.dart';
import 'models.dart';
import 'phone_server.dart' show kServiceType;

/// iOS side of the link: discovers the Mac over Bonjour (nsd) and keeps one
/// LineConnection to it, ported from iOS/MacLink.swift.
class MacLink {
  MacLink({this.deviceName = 'iPhone'});

  final String deviceName;

  final _faces = StreamController<FaceState>.broadcast();
  final _packets = StreamController<Packet>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final _macs = StreamController<List<String>>.broadcast();

  Stream<FaceState> get faces => _faces.stream;
  Stream<Packet> get packets => _packets.stream;
  Stream<bool> get connected => _connected.stream;
  Stream<List<String>> get macs => _macs.stream;

  String? macName;
  bool get isConnected => _link != null;

  LineConnection? _link;
  nsd.Discovery? _discovery;
  Timer? _retry;

  Future<void> start() async {
    _discovery = await nsd.startDiscovery(kServiceType);
    _discovery!.addServiceListener((service, status) {
      if (status != nsd.ServiceStatus.found) return;
      _macs.add([service.name ?? 'Mac']);
      if (_link == null && service.host != null && service.port != null) {
        _connect(service.host!, service.port!);
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
      link.packets.listen((packet) {
        if (packet.hello != null) macName = packet.hello;
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
