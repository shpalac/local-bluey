import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/retry.dart';

void main() {
  test('succeeds after transient failures', () async {
    var attempts = 0;
    final result = await withRetry(() async {
      attempts++;
      if (attempts < 3) throw const SocketException('drop');
      return 'ok';
    }, initialDelay: Duration.zero);
    expect(result, 'ok');
    expect(attempts, 3);
  });

  test('gives up after maxAttempts and rethrows', () async {
    var attempts = 0;
    await expectLater(
      withRetry(() async {
        attempts++;
        throw const SocketException('down');
      }, initialDelay: Duration.zero),
      throwsA(isA<SocketException>()),
    );
    expect(attempts, 3);
  });

  test('non-retryable errors fail immediately', () async {
    var attempts = 0;
    await expectLater(
      withRetry(
        () async {
          attempts++;
          throw ArgumentError('bad request');
        },
        initialDelay: Duration.zero,
        shouldRetry: (e) => e is SocketException,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(attempts, 1);
  });
}
