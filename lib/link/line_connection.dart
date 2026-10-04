import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Newline-delimited JSON [Packet]s over one socket, ported from LineConnection in
/// Shared/GooglyLink.swift.
class LineConnection {
  LineConnection(this._socket);

  final Socket _socket;
  final _onPacket = StreamController<Packet>.broadcast();
  final _onDone = StreamController<void>.broadcast();
  String _buffer = '';
  bool _started = false;

  Stream<Packet> get packets => _onPacket.stream;
  Stream<void> get done => _onDone.stream;

  void start() {
    if (_started) return;
    _started = true;
    _socket.setOption(SocketOption.tcpNoDelay, true);
    utf8.decoder
        .bind(_socket)
        .listen(
          (chunk) {
            _buffer += chunk;
            int newline;
            while ((newline = _buffer.indexOf('\n')) >= 0) {
              final line = _buffer.substring(0, newline);
              _buffer = _buffer.substring(newline + 1);
              if (line.isEmpty) continue;
              try {
                _onPacket.add(
                  Packet.fromJson(
                    Map<String, dynamic>.from(jsonDecode(line) as Map),
                  ),
                );
              } catch (_) {
                // Ignore malformed lines, matching the Swift `try?`.
              }
            }
          },
          onDone: () {
            _onDone.add(null);
            close();
          },
          onError: (_) {
            _onDone.add(null);
            close();
          },
        );
  }

  void send(Packet packet) {
    _socket.write('${jsonEncode(packet.toJson())}\n');
  }

  Future<void> close() async {
    await _socket.close();
    await _onPacket.close();
    await _onDone.close();
  }
}
