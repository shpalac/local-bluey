import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Newline-delimited JSON [Packet]s over one socket, ported from LineConnection in
/// Shared/GooglyLink.swift.
class LineConnection {
  LineConnection(this._socket);

  /// Largest buffered backlog accepted before the connection is dropped;
  /// measured in BYTES (#115), not UTF-16 code units.
  static const maxFrameBytes = 16 * 1024 * 1024;

  final Socket _socket;
  final _onPacket = StreamController<Packet>.broadcast();
  final _onDone = StreamController<void>.broadcast();

  /// Incoming text is kept as a list of pieces and joined only when a
  /// newline arrives - appending to one growing string cost O(n^2) copies
  /// on large base64 audio frames (#115).
  final List<String> _pieces = [];
  int _pendingBytes = 0;

  bool _started = false;
  bool _closed = false;
  bool _doneEmitted = false;

  bool get isClosed => _closed;

  Stream<Packet> get packets => _onPacket.stream;
  Stream<void> get done => _onDone.stream;

  void start() {
    if (_started) return;
    _started = true;
    _socket.setOption(SocketOption.tcpNoDelay, true);
    utf8.decoder
        .bind(_socket)
        .listen(_onChunk, onDone: close, onError: (_) => close());
  }

  void _onChunk(String chunk) {
    if (_closed) return;
    _pieces.add(chunk);
    _pendingBytes += utf8.encode(chunk).length;
    if (_pendingBytes > maxFrameBytes) {
      // A runaway peer: drop the connection rather than buffer forever.
      close();
      return;
    }
    if (!chunk.contains('\n')) return;
    // One join + split per batch of completed lines: linear overall (#115).
    final lines = _pieces.join().split('\n');
    final tail = lines.removeLast();
    _pieces
      ..clear()
      ..add(tail);
    _pendingBytes = utf8.encode(tail).length;
    for (final line in lines) {
      if (line.isEmpty) continue;
      try {
        _onPacket.add(
          Packet.fromJson(Map<String, dynamic>.from(jsonDecode(line) as Map)),
        );
      } catch (_) {
        // Ignore malformed lines, matching the Swift `try?`.
      }
    }
  }

  void send(Packet packet) {
    if (_closed) return;
    try {
      _socket.write('${jsonEncode(packet.toJson())}\n');
    } catch (_) {
      close();
    }
  }

  /// Idempotent. Emits done exactly once, including on LOCAL closes (#113):
  /// listeners (PhoneServer, MacLink) learn about every disconnect and can
  /// drop the dead link instead of keeping ghost phones.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _socket.close();
    } catch (_) {}
    _emitDone();
    if (!_onPacket.isClosed) await _onPacket.close();
    if (!_onDone.isClosed) await _onDone.close();
  }

  void _emitDone() {
    if (_doneEmitted) return;
    _doneEmitted = true;
    _onDone.add(null);
  }
}
