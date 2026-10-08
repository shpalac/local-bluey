import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/services/speak_receipts.dart';

void main() {
  test('#87: spoken replies are tracked, acks clear them', () async {
    final receipts = SpeakReceipts(timeout: const Duration(seconds: 30));
    final packet = Packet(command: 'say', text: 'hi');
    final id = receipts.track(packet, 'hi');
    expect(packet.speech, id);
    expect(receipts.hasPending, isTrue);
    receipts.ack(id);
    expect(receipts.hasPending, isFalse);
    expect(receipts.failureLog, isEmpty);
    receipts.dispose();
  });

  test('#87: missing receipt is logged as a failure', () async {
    final receipts = SpeakReceipts(timeout: Duration.zero);
    final failures = <String>[];
    receipts.failures.listen(failures.add);
    receipts.track(Packet(command: 'say', text: 'answer'), 'answer');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(receipts.failureLog, hasLength(1));
    expect(receipts.failureLog.single, contains('answer'));
    expect(failures, hasLength(1));
    receipts.dispose();
  });

  test('#87: silent actions get no receipt tracking', () {
    final receipts = SpeakReceipts();
    // Silent tool-only replies never call track().
    expect(receipts.hasPending, isFalse);
    expect(receipts.failureLog, isEmpty);
    receipts.dispose();
  });

  test('#87: manual retry returns the stored packet', () {
    final receipts = SpeakReceipts(timeout: const Duration(seconds: 30));
    final packet = Packet(command: 'say', text: 'retry me');
    final id = receipts.track(packet, 'retry me');
    expect(receipts.retryPacket(id), same(packet));
    expect(receipts.lastSpeech, id);
    receipts.dispose();
  });

  test('#255: acknowledged replies stay within the count cap', () {
    final receipts = SpeakReceipts(
      timeout: const Duration(seconds: 30),
      maxRetainedReplies: 3,
    );
    final ids = <int>[];
    for (var i = 0; i < 10; i++) {
      final id = receipts.track(
        Packet(command: 'say', text: 'r$i', audio: 'A' * 100),
        'r$i',
      );
      receipts.ack(id);
      ids.add(id);
    }
    expect(receipts.retryPacket(ids.last), isNotNull);
    expect(receipts.retryPacket(ids[6]), isNull);
    expect(receipts.retryPacket(ids[7]), isNotNull);
    receipts.dispose();
  });

  test('#255: byte cap evicts oldest, keeps newest even when oversized', () {
    final receipts = SpeakReceipts(
      timeout: const Duration(seconds: 30),
      maxRetainedBytes: 250,
    );
    final a = receipts.track(Packet(command: 'say', audio: 'A' * 100), 'a');
    final b = receipts.track(Packet(command: 'say', audio: 'B' * 100), 'b');
    expect(receipts.retryPacket(a), isNotNull);
    final c = receipts.track(Packet(command: 'say', audio: 'C' * 100), 'c');
    expect(receipts.retryPacket(a), isNull);
    expect(receipts.retryPacket(b), isNotNull);
    final big = receipts.track(Packet(command: 'say', audio: 'D' * 900), 'd');
    expect(receipts.retryPacket(big), isNotNull);
    expect(receipts.retryPacket(c), isNull);
    receipts.dispose();
  });

  test('#255: age window forgets old replies and cancels their timers', () {
    var t = DateTime(2026, 1, 1, 12);
    final receipts = SpeakReceipts(
      timeout: const Duration(hours: 1),
      retention: const Duration(minutes: 2),
      now: () => t,
    );
    final old = receipts.track(Packet(command: 'say', audio: 'x'), 'old');
    expect(receipts.hasPending, isTrue);
    t = t.add(const Duration(minutes: 3));
    final fresh = receipts.track(Packet(command: 'say', audio: 'y'), 'new');
    expect(receipts.retryPacket(old), isNull);
    expect(receipts.retryPacket(fresh), isNotNull);
    receipts.ack(fresh);
    expect(receipts.hasPending, isFalse);
    receipts.dispose();
  });

  test('#255: failure log is capped', () async {
    final receipts = SpeakReceipts(timeout: Duration.zero, maxFailureLines: 3);
    for (var i = 0; i < 8; i++) {
      receipts.track(Packet(command: 'say', text: 'm$i'), 'm$i');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(receipts.failureLog.length, lessThanOrEqualTo(3));
    receipts.dispose();
  });

  test(
    '#255: dispose clears payloads and history, no later failures',
    () async {
      final receipts = SpeakReceipts(timeout: const Duration(milliseconds: 5));
      final failures = <String>[];
      receipts.failures.listen(failures.add);
      final id = receipts.track(Packet(command: 'say', audio: 'z'), 'z');
      receipts.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(receipts.retryPacket(id), isNull);
      expect(receipts.failureLog, isEmpty);
      expect(failures, isEmpty);
    },
  );
}
