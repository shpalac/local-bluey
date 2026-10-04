import 'dart:async';

import '../link/models.dart';

/// Delivery receipts for spoken replies (#87): every 'say' broadcast carries
/// a speech id; the phone acks with 'playing'/'done'. A missing receipt
/// within [timeout] is logged as a failure; silent actions get no tracking.
class SpeakReceipts {
  SpeakReceipts({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  int _next = 1;
  final _pending = <int, Timer>{};
  final _spoken = <int, String>{};
  final _packets = <int, Packet>{};
  final _failureLog = <String>[];
  final _failures = StreamController<String>.broadcast();

  /// One entry per missed receipt, newest last.
  List<String> get failureLog => List.unmodifiable(_failureLog);

  /// Fires when a receipt times out, with the log line.
  Stream<String> get failures => _failures.stream;

  bool get hasPending => _pending.isNotEmpty;

  /// Assigns a speech id to a spoken reply and starts the receipt timer.
  /// Call only for replies that are actually spoken (#87).
  int track(Packet say, String spoken) {
    final id = _next++;
    say.speech = id;
    _spoken[id] = spoken;
    _packets[id] = say;
    _pending[id] = Timer(timeout, () => _miss(id));
    return id;
  }

  /// A 'playing' or 'done' ack from the phone clears the receipt.
  void ack(int? speech) {
    if (speech == null) return;
    _pending.remove(speech)?.cancel();
  }

  /// The packet to re-broadcast for a manual retry, if still known.
  Packet? retryPacket(int speech) => _packets[speech];

  /// Speech id of the most recent tracked reply, for manual retry.
  int? get lastSpeech => _spoken.isEmpty ? null : _spoken.keys.last;

  void _miss(int id) {
    _pending.remove(id);
    final text = _spoken[id] ?? '';
    final line =
        'No receipt from phone for: '
        '${text.length > 40 ? '${text.substring(0, 40)}…' : text}';
    _failureLog.add(line);
    _failures.add(line);
  }

  void dispose() {
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    _failures.close();
  }
}
