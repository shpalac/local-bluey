import 'dart:async';
import 'dart:io' show SocketException;

/// Conservative typed transport default, never backend error-text inference.
/// Generic client/status/parse/programming failures are not retryable. Socket
/// errors and timeouts are the supported transient types; no HTTP status retry.
bool retryableTransportError(Object error) =>
    error is SocketException || error is TimeoutException;

/// Retries supported transient failures with bounded exponential backoff (#62).
/// Defaults to socket/timeout only. [shouldRetry] explicitly replaces that rule;
/// predicate or [onRetry] errors propagate immediately, not as another attempt.
/// Callback fires only before an actual retry. Max attempts 1..10, initial delay
/// 0..60 seconds; subsequent delays cap at 60 seconds. No whole-call deadline,
/// cancellation, backend idempotency or billing guarantee is implied.
Future<T> withRetry<T>(
  Future<T> Function() call, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 300),
  bool Function(Object error)? shouldRetry,
  void Function(int attempt, Object error)? onRetry,
}) async {
  if (maxAttempts < 1 || maxAttempts > 10) {
    throw ArgumentError.value(maxAttempts, 'maxAttempts', 'Must be 1..10');
  }
  if (initialDelay < Duration.zero ||
      initialDelay > const Duration(seconds: 60)) {
    throw ArgumentError.value(
      initialDelay,
      'initialDelay',
      'Must be 0..60 seconds',
    );
  }
  var attempt = 0;
  var delay = initialDelay;
  while (true) {
    attempt++;
    try {
      return await call();
    } catch (error) {
      if (attempt >= maxAttempts) rethrow;
      if (!(shouldRetry ?? retryableTransportError)(error)) rethrow;
      onRetry?.call(attempt, error);
      await Future<void>.delayed(delay);
      delay = Duration(
        microseconds: (delay.inMicroseconds * 2).clamp(0, 60000000),
      );
    }
  }
}
