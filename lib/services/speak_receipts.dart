import 'dart:async';
import 'dart:convert';

import '../link/models.dart';

/// Delivery receipts for spoken replies (#87): every 'say' broadcast carries
/// a speech id; the phone acks with 'playing'/'done'. A missing receipt
/// within [timeout] is logged as a failure; silent actions get no tracking.
class SpeakReceipts {
  SpeakReceipts({
    this.timeout = const Duration(seconds: 15),
    this.retention = defaultRetention,
    this.maxRetainedBytes = defaultMaxRetainedBytes,
    this.maxRetainedReplies = defaultMaxRetainedReplies,
    this.maxFailureLines = defaultMaxFailureLines,
    DateTime Function()? now,
  }) : assert(!timeout.isNegative),
       assert(!retention.isNegative),
       assert(maxRetainedBytes >= 0),
       assert(maxRetainedReplies >= 0),
       assert(maxFailureLines >= 0),
       _now = now ?? DateTime.now;

  /// Default retry lifetime, measured from first delivery (not acknowledgement).
  static const defaultRetention = Duration(minutes: 2);

  /// Default encoded retry payload budget: 8 MiB.
  static const defaultMaxRetainedBytes = 8 * 1024 * 1024;

  /// Default maximum number of retryable replies.
  static const defaultMaxRetainedReplies = 20;

  /// Default maximum number of missed-receipt diagnostics.
  static const defaultMaxFailureLines = 20;

  /// How long to wait for the phone's receipt before logging a failure.
  final Duration timeout;

  /// Retry window (#255): a reply is forgotten at this age, even when idle.
  final Duration retention;

  /// Strict cap on UTF-8 bytes of base64 audio, packet text and spoken text.
  /// This is a payload budget, not a measurement of Dart heap overhead.
  final int maxRetainedBytes;

  /// Cap on how many replies stay retryable.
  final int maxRetainedReplies;

  /// Cap on failure-log lines kept.
  final int maxFailureLines;

  final DateTime Function() _now;

  int _next = 1;
  Timer? _expiryTimer;
  bool _disposed = false;
  final _pending = <int, Timer>{};
  final _spoken = <int, String>{};
  final _packets = <int, Packet>{};
  final _sizes = <int, int>{};
  final _times = <int, DateTime>{};
  int _retainedBytes = 0;
  final _failureLog = <String>[];
  final _failures = StreamController<String>.broadcast();

  /// One entry per missed receipt, newest last.
  List<String> get failureLog => List.unmodifiable(_failureLog);

  /// Fires when a receipt times out, with the log line.
  Stream<String> get failures => _failures.stream;

  /// Whether any spoken reply is still waiting on its receipt.
  bool get hasPending => _pending.isNotEmpty;

  /// Number of packets still eligible for retry.
  int get retainedReplies {
    _evict();
    return _packets.length;
  }

  /// Encoded payload bytes still retained for retry.
  int get retainedBytes {
    _evict();
    return _retainedBytes;
  }

  /// Assigns a speech id to a spoken reply and starts the receipt timer.
  /// Call only for replies that are actually spoken (#87).
  int track(Packet say, String spoken) {
    if (_disposed) throw StateError('SpeakReceipts is disposed');
    final id = _next++;
    say.speech = id;
    final size =
        utf8.encode(say.audio ?? '').length +
        utf8.encode(say.text ?? '').length +
        utf8.encode(spoken).length;
    _spoken[id] = spoken;
    _packets[id] = say;
    _sizes[id] = size;
    _times[id] = _now();
    _retainedBytes += size;
    _pending[id] = Timer(timeout, () => _miss(id));
    _evict();
    return id;
  }

  /// Drops replies past the retry window or over the count/byte caps,
  /// oldest first, cancelling any receipt timer they still hold (#255).
  /// Even the sole/newest packet is evicted if it exceeds a limit. The
  /// caller still broadcasts its original packet with the assigned speech id.
  void _evict() {
    final cutoff = _now().subtract(retention);
    while (_packets.isNotEmpty) {
      final oldest = _packets.keys.first;
      final expired = !_times[oldest]!.isAfter(cutoff);
      if (!expired &&
          _packets.length <= maxRetainedReplies &&
          _retainedBytes <= maxRetainedBytes) {
        break;
      }
      _forget(oldest);
    }
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (_packets.isNotEmpty) {
      final expires = _times[_packets.keys.first]!.add(retention);
      _expiryTimer = Timer(expires.difference(_now()), _evict);
    }
  }

  void _forget(int id) {
    _pending.remove(id)?.cancel();
    _spoken.remove(id);
    _packets.remove(id);
    _times.remove(id);
    _retainedBytes -= _sizes.remove(id) ?? 0;
  }

  /// Host reply boundary: track remote delivery only when the broadcast
  /// actually has authenticated recipients. Local playback is independent.
  void deliver(
    Packet packet,
    String spoken,
    int Function(Packet, {void Function(int recipients)? beforeSend}) broadcast,
  ) {
    broadcast(
      packet,
      beforeSend: (recipients) {
        if (recipients > 0) track(packet, spoken);
      },
    );
  }

  /// A 'playing' or 'done' ack from the phone clears the receipt.
  void ack(int? speech) {
    if (speech == null) return;
    _pending.remove(speech)?.cancel();
  }

  /// The packet to re-broadcast for a manual retry, if still known.
  Packet? retryPacket(int speech) {
    _evict();
    return _packets[speech];
  }

  /// Speech id of the most recent tracked reply, for manual retry.
  int? get lastSpeech {
    _evict();
    return _packets.isEmpty ? null : _packets.keys.last;
  }

  void _miss(int id) {
    _evict();
    if (_pending.remove(id) == null) return;
    final text = _spoken[id] ?? '';
    final line =
        'Phone delivery: no receipt for: '
        '${text.length > 40 ? '${text.substring(0, 40)}…' : text}';
    _failureLog.add(line);
    while (_failureLog.length > maxFailureLines) {
      _failureLog.removeAt(0);
    }
    if (!_failures.isClosed) _failures.add(line);
  }

  /// Cancels all pending timers, drops retained payloads and history, and
  /// closes the failure stream.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    _spoken.clear();
    _packets.clear();
    _sizes.clear();
    _times.clear();
    _retainedBytes = 0;
    _failureLog.clear();
    _failures.close();
  }
}
