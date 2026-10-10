import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';

/// Narrow owned byte transport; production delegates to its Socket.
abstract interface class LineTransport {
  /// Single inbound byte stream owned by this connection.
  Stream<List<int>> get input;

  /// Sets transport options before subscribing.
  void configure();

  /// Writes one encoded JSON line.
  void write(String line);

  /// Starts best-effort output drain; completion is not logical close.
  Future<void> close();

  /// Forces release; no drain is required for logical closure.
  void destroy();
}

class _SocketTransport implements LineTransport {
  _SocketTransport(this.socket);
  final Socket socket;
  @override
  Stream<List<int>> get input => socket;
  @override
  void configure() => socket.setOption(SocketOption.tcpNoDelay, true);
  @override
  void write(String line) => socket.write(line);
  @override
  Future<void> close() async {
    await socket.close();
  }

  @override
  void destroy() => socket.destroy();
}

/// Newline-delimited JSON [Packet]s over one owned socket. No protocol or
/// authentication decisions are made here; malformed lines remain ignored.
class LineConnection {
  LineConnection(Socket socket) : this.withTransport(_SocketTransport(socket));

  /// Narrow fixture seam; cap defaults to the production wire-frame limit.
  LineConnection.withTransport(
    this._transport, {
    int frameLimit = maxFrameBytes,
    this.closeTimeout = const Duration(seconds: 2),
  }) : _frameLimit = frameLimit {
    if (frameLimit < 1) throw ArgumentError.value(frameLimit, 'frameLimit');
    if (closeTimeout <= Duration.zero) {
      throw ArgumentError.value(closeTimeout, 'closeTimeout');
    }
  }

  /// Largest individual wire frame before LF, in bytes (including CR, #115).
  /// Coalesced valid frames never count against each other's limit.
  static const maxFrameBytes = 16 * 1024 * 1024;

  /// Finite best-effort drain and input cleanup deadline before force destroy.
  final Duration closeTimeout;

  final LineTransport _transport;
  final int _frameLimit;
  final _onPacket = StreamController<Packet>.broadcast();
  final _onDone = StreamController<void>.broadcast();
  final _tail = BytesBuilder(copy: false);
  int _pendingBytes = 0;
  StreamSubscription<List<int>>? _subscription;
  Future<void>? _closing;
  bool _started = false, _closed = false;

  /// True immediately when logical close begins, not after outbound drain.
  bool get isClosed => _closed;

  /// Incoming valid packets; none are added after logical closure.
  Stream<Packet> get packets => _onPacket.stream;

  /// One disconnect notification, including local close (#113).
  Stream<void> get done => _onDone.stream;

  /// Starts consumption once. Starting after closure is a no-op.
  void start() {
    if (_started || _closed) return;
    _started = true;
    try {
      _transport.configure();
      _subscription = _transport.input.listen(
        _onChunk,
        onDone: () => unawaited(close()),
        onError: (Object _) => unawaited(close()),
      );
    } catch (_) {
      unawaited(close());
    }
  }

  void _onChunk(List<int> chunk) {
    if (_closed) return;
    var start = 0;
    for (var i = 0; i <= chunk.length; i++) {
      if (i < chunk.length && chunk[i] != 10) continue;
      final count = i - start;
      if (_pendingBytes + count > _frameLimit) {
        unawaited(close());
        return;
      }
      if (count > 0) {
        _tail.add(Uint8List.fromList(chunk.sublist(start, i)));
        _pendingBytes += count;
      }
      if (i == chunk.length) return;
      final bytes = _tail.takeBytes();
      _pendingBytes = 0;
      if (bytes.isNotEmpty) {
        try {
          final line = utf8.decode(bytes);
          _onPacket.add(
            Packet.fromJson(Map<String, dynamic>.from(jsonDecode(line) as Map)),
          );
        } catch (_) {
          // Ignore malformed lines, matching the Swift try?.
        }
      }
      if (_closed) return;
      start = i + 1;
    }
  }

  /// Writes only while logically open. Write failure initiates close.
  void send(Packet packet) {
    if (_closed) return;
    try {
      _transport.write('${jsonEncode(packet.toJson())}\n');
    } catch (_) {
      unawaited(close());
    }
  }

  /// Idempotent logical teardown clears tail, emits done and stops input now.
  /// One shared future completes after best-effort drain/input cleanup or the
  /// finite [closeTimeout], then force release. Successful drain preserves queued
  /// outbound data; timeout/error makes delivery best-effort, not guaranteed.
  /// Paused packet/done consumers do not hold transport teardown open. Packets
  /// already queued before close are not retrospectively retracted.
  Future<void> close() {
    if (_closing != null) return _closing!;
    final completion = Completer<void>();
    _closing = completion.future;
    _closed = true;
    _tail.clear();
    _pendingBytes = 0;
    _onDone.add(null);
    final subscription = _subscription;
    _subscription = null;
    final cleanup = <Future<void>>[
      if (subscription != null) _consumeCleanup(subscription.cancel),
      _consumeCleanup(_transport.close),
    ];
    unawaited(_onPacket.close());
    unawaited(_onDone.close());
    unawaited(() async {
      try {
        await Future.wait(cleanup).timeout(closeTimeout);
      } catch (_) {
        // Finite deadline; late cleanup errors are consumed independently.
      } finally {
        try {
          _transport.destroy();
        } catch (_) {}
        completion.complete();
      }
    }());
    return _closing!;
  }

  Future<void> _consumeCleanup(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }
}
