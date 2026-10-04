import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Newline-delimited JSON [Packet]s over one socket, ported from LineConnection in
/// Shared/GooglyLink.swift.
class LineConnection {
  LineConnection(this._socket);

  /// Largest single frame accepted; anything bigger kills the connection
  /// instead of growing memory without bound.
  static const maxFrameBytes = 16 * 1024 * 1024;

  final Socket _socket;
  final _onPacket = StreamController<Packet>.broadcast();
  final _onDone = StreamController<void>.broadcast();
  String _buffer = '';
  bool _started = false;
  bool _closed = false;

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
            if (_buffer.length > maxFrameBytes) {
              // A runaway peer: drop the connection rather than buffer forever.
              close();
              return;
            }
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
    if (_closed) return;
    try {
      _socket.write('${jsonEncode(packet.toJson())}\n');
    } catch (_) {
      close();
    }
  }

  /// Idempotent: repeated calls (done + error + explicit stop) are no-ops.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _socket.close();
    } catch (_) {}
    if (!_onPacket.isClosed) await _onPacket.close();
    if (!_onDone.isClosed) await _onDone.close();
  }
}
