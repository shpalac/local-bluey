import 'dart:convert';

import 'package:fake_async/fake_async.dart';
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

  test('#255: many acknowledgements obey count and encoded byte caps', () {
    fakeAsync((async) {
      final receipts = SpeakReceipts(
        now: async.getClock(DateTime(2026)).now,
        maxRetainedReplies: 3,
        maxRetainedBytes: 250,
      );
      final ids = <int>[];
      for (var i = 0; i < 1000; i++) {
        final id = receipts.track(
          Packet(command: 'say', text: 'שלום', audio: 'A' * 100),
          'שלום',
        );
        receipts.ack(id);
        ids.add(id);
        expect(receipts.retainedReplies, lessThanOrEqualTo(3));
        expect(receipts.retainedBytes, lessThanOrEqualTo(250));
        expect(receipts.hasPending, isFalse);
      }
      expect(receipts.retainedReplies, 2);
      expect(receipts.retainedBytes, 232);
      expect(receipts.retryPacket(ids[997]), isNull);
      expect(receipts.retryPacket(ids[998]), isNotNull);
      expect(receipts.retryPacket(ids.last), isNotNull);
      expect(receipts.failureLog, isEmpty);
      receipts.dispose();
    });
  });

  test('#255: count eviction cancels timers and cannot revive an ID', () {
    fakeAsync((async) {
      final receipts = SpeakReceipts(
        now: async.getClock(DateTime(2026)).now,
        maxRetainedReplies: 1,
      );
      final old = receipts.track(Packet(command: 'say'), 'old');
      final fresh = receipts.track(Packet(command: 'say'), 'fresh');
      receipts.ack(fresh);
      expect(receipts.retryPacket(old), isNull);
      receipts.ack(old);
      expect(receipts.hasPending, isFalse);
      async.elapse(const Duration(seconds: 30));
      expect(receipts.failureLog, isEmpty);
      expect(receipts.retryPacket(old), isNull);
      receipts.dispose();
    });
  });

  test('#255: sole reply expires at the boundary without another reply', () {
    fakeAsync((async) {
      final receipts = SpeakReceipts(
        timeout: const Duration(minutes: 5),
        retention: const Duration(minutes: 2),
        now: async.getClock(DateTime(2026)).now,
      );
      final id = receipts.track(Packet(command: 'say', audio: 'x'), 'old');
      async.elapse(
        const Duration(minutes: 2) - const Duration(microseconds: 1),
      );
      expect(receipts.retryPacket(id), isNotNull);
      async.elapse(const Duration(microseconds: 1));
      expect(receipts.hasPending, isFalse);
      expect(receipts.lastSpeech, isNull);
      expect(receipts.retainedReplies, 0);
      expect(receipts.retainedBytes, 0);
      expect(receipts.retryPacket(id), isNull);
      async.elapse(const Duration(minutes: 5));
      expect(receipts.failureLog, isEmpty);
      receipts.dispose();
    });
  });

  test('#255: oversized packets are delivered but are never retryable', () {
    fakeAsync((async) {
      final receipts = SpeakReceipts(
        maxRetainedBytes: 10,
        now: async.getClock(DateTime(2026)).now,
      );
      final packet = Packet(command: 'say', text: 'שלום', audio: 'AAAA');
      Packet? delivered;
      receipts.deliver(packet, 'שלום', (
        value, {
        void Function(int recipients)? beforeSend,
      }) {
        beforeSend?.call(1);
        delivered = value;
        return 1;
      });
      expect(delivered, same(packet));
      expect(packet.audio, 'AAAA');
      expect(packet.speech, isNotNull);
      expect(receipts.retryPacket(packet.speech!), isNull);
      expect(receipts.lastSpeech, isNull);
      expect(receipts.retainedReplies, 0);
      expect(receipts.retainedBytes, 0);
      expect(receipts.hasPending, isFalse);
      async.elapse(const Duration(seconds: 30));
      expect(receipts.failureLog, isEmpty);
      receipts.dispose();
    });
  });

  test('#255: UTF-8 packet text and spoken text both count toward the cap', () {
    final text = 'שלום 😀';
    final size = 4 + utf8.encode(text).length + utf8.encode('different').length;
    final receipts = SpeakReceipts(maxRetainedBytes: size);
    final exact = receipts.track(
      Packet(command: 'say', audio: 'AAAA', text: text),
      'different',
    );
    expect(receipts.retainedBytes, size);
    expect(receipts.retryPacket(exact), isNotNull);
    final over = receipts.track(
      Packet(command: 'say', audio: 'AAAAA', text: text),
      'different',
    );
    expect(receipts.retryPacket(exact), isNull);
    expect(receipts.retryPacket(over), isNull);
    expect(receipts.retainedBytes, 0);
    receipts.dispose();
  });

  test('#255: zero retry budgets retain nothing', () {
    for (final receipts in [
      SpeakReceipts(maxRetainedReplies: 0),
      SpeakReceipts(maxRetainedBytes: 0),
      SpeakReceipts(retention: Duration.zero),
    ]) {
      final id = receipts.track(Packet(command: 'say', audio: 'x'), 'x');
      expect(receipts.retryPacket(id), isNull);
      expect(receipts.retainedReplies, 0);
      expect(receipts.retainedBytes, 0);
      expect(receipts.hasPending, isFalse);
      receipts.dispose();
    }
  });

  test('#255: many timeouts cap failure history and expire payloads', () {
    fakeAsync((async) {
      final receipts = SpeakReceipts(
        now: async.getClock(DateTime(2026)).now,
        timeout: const Duration(seconds: 1),
        maxFailureLines: 3,
        maxRetainedReplies: 4,
        maxRetainedBytes: 100,
      );
      final failures = <String>[];
      receipts.failures.listen(failures.add);
      for (var i = 0; i < 100; i++) {
        receipts.track(Packet(command: 'say', audio: 'A' * 10), 'm$i');
        async.elapse(const Duration(seconds: 1));
        expect(receipts.hasPending, isFalse);
        expect(receipts.retainedReplies, lessThanOrEqualTo(4));
        expect(receipts.retainedBytes, lessThanOrEqualTo(100));
        expect(receipts.failureLog.length, lessThanOrEqualTo(3));
      }
      expect(failures, hasLength(100));
      expect(receipts.failureLog.first, contains('m97'));
      expect(receipts.failureLog.last, contains('m99'));
      async.elapse(const Duration(minutes: 2));
      expect(receipts.retainedReplies, 0);
      expect(receipts.retainedBytes, 0);
      receipts.dispose();
    });
  });

  test('#255: dispose clears all state and emits no later failure', () {
    fakeAsync((async) {
      final receipts = SpeakReceipts(
        now: async.getClock(DateTime(2026)).now,
        timeout: const Duration(seconds: 1),
      );
      final failures = <String>[];
      receipts.failures.listen(failures.add);
      receipts.track(Packet(command: 'say'), 'missed');
      async.elapse(const Duration(seconds: 1));
      expect(receipts.failureLog, hasLength(1));
      final id = receipts.track(Packet(command: 'say', audio: 'z'), 'pending');
      receipts.dispose();
      async.elapse(const Duration(minutes: 10));
      expect(receipts.retryPacket(id), isNull);
      expect(receipts.lastSpeech, isNull);
      expect(receipts.retainedReplies, 0);
      expect(receipts.retainedBytes, 0);
      expect(receipts.hasPending, isFalse);
      expect(receipts.failureLog, isEmpty);
      expect(failures, hasLength(1));
      expect(async.nonPeriodicTimerCount, 0);
      expect(async.periodicTimerCount, 0);
      expect(
        () => receipts.track(Packet(command: 'say'), 'after disposal'),
        throwsStateError,
      );
      receipts.dispose();
    });
  });
}
