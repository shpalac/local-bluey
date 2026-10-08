import 'dart:async';

import '../link/models.dart';

/// Delivery receipts for spoken replies (#87): every 'say' broadcast carries
/// a speech id; the phone acks with 'playing'/'done'. A missing receipt
/// within [timeout] is logged as a failure; silent actions get no tracking.
class SpeakReceipts {
  SpeakReceipts({
    this.timeout = const Duration(seconds: 15),
    this.retention = const Duration(minutes: 2),
    this.maxRetainedBytes = 8 * 1024 * 1024,
    this.maxRetainedReplies = 20,
    this.maxFailureLines = 20,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// How long to wait for the phone's receipt before logging a failure.
  final Duration timeout;

  /// Retry window (#255): a reply older than this is forgotten.
  final Duration retention;

  /// Cap on retained reply payload (audio plus text), in bytes.
  final int maxRetainedBytes;

  /// Cap on how many replies stay retryable.
  final int maxRetainedReplies;

  /// Cap on failure-log lines kept.
  final int maxFailureLines;

  final DateTime Function() _now;

  int _next = 1;
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

  /// Assigns a speech id to a spoken reply and starts the receipt timer.
  /// Call only for replies that are actually spoken (#87).
  int track(Packet say, String spoken) {
    final id = _next++;
    say.speech = id;
    final size = (say.audio?.length ?? 0) + spoken.length;
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
  /// The newest reply is always kept.
  void _evict() {
    final cutoff = _now().subtract(retention);
    while (_packets.length > 1) {
      final oldest = _packets.keys.first;
      final expired = _times[oldest]!.isBefore(cutoff);
      if (!expired &&
          _packets.length <= maxRetainedReplies &&
          _retainedBytes <= maxRetainedBytes) {
        break;
      }
      _forget(oldest);
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
  int? get lastSpeech => _spoken.isEmpty ? null : _spoken.keys.last;

  void _miss(int id) {
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
