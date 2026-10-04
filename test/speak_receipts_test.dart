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
}
