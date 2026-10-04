import 'dart:async';

/// Retries a network call with exponential backoff (#62).
///
/// Only transport failures (socket errors, timeouts, 5xx-style exceptions
/// surfaced by the http client) are retried; a well-formed error reply from
/// the server is returned as-is by the caller, not thrown here.
Future<T> withRetry<T>(
  Future<T> Function() call, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 300),
  bool Function(Object error)? shouldRetry,
  void Function(int attempt, Object error)? onRetry,
}) async {
  var attempt = 0;
  var delay = initialDelay;
  while (true) {
    attempt++;
    try {
      return await call();
    } catch (error) {
      final retryable = shouldRetry?.call(error) ?? true;
      if (!retryable || attempt >= maxAttempts) rethrow;
      onRetry?.call(attempt, error);
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }
}
