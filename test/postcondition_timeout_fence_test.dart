import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/postcondition_verifier.dart';

void main() {
  test(
    'ac2 timeout does not start later postcondition reads',
    () async {
      final reader = _BlockingReader();
      final verifier = PostconditionVerifier(reader);
      final pending = verifier.verify(
        [
          Postcondition.parse('ax:button=Done'),
          Postcondition.parse('tool:status=ok'),
        ],
        timeout: const Duration(milliseconds: 10),
      );

      await reader.firstStarted.future;
      expect(await pending, VerificationOutcome.inconclusive);

      reader.releaseFirst.complete('Done');
      await Future<void>.delayed(Duration.zero);
      expect(reader.keys, ['button']);
    },
  );

  test(
    'ac3 cancellation does not start later postcondition reads',
    () async {
      final reader = _BlockingReader();
      final cancellation = VerificationCancellation();
      final pending = PostconditionVerifier(reader).verify(
        [
          Postcondition.parse('ax:button=Done'),
          Postcondition.parse('file:receipt=present'),
        ],
        timeout: const Duration(seconds: 1),
        cancellation: cancellation,
      );

      await reader.firstStarted.future;
      cancellation.cancel();
      reader.releaseFirst.complete('Done');

      expect(await pending, VerificationOutcome.cancelled);
      expect(reader.keys, ['button']);
    },
  );
}

final class _BlockingReader implements PostconditionReader {
  final firstStarted = Completer<void>();
  final releaseFirst = Completer<String?>();
  final keys = <String>[];

  @override
  Future<String?> read(Postcondition condition) {
    keys.add(condition.key);
    if (keys.length == 1) {
      firstStarted.complete();
      return releaseFirst.future;
    }
    return Future<String?>.value('ok');
  }
}
