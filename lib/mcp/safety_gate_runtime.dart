import 'dart:async';

import 'mcp_tool_safety_gate.dart';

/// A cooperative cancellation signal for an in-flight MCP invocation.
///
/// Completing [cancel] stops waiting for the tool result, but it cannot undo
/// a side effect already performed by the tool or terminate its transport.
class McpCancellationSignal {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

/// Production boundary helpers for MCP execution.
///
/// Approval remains the responsibility of [McpToolSafetyGate]. This runtime
/// only handles cancellation and redacts returned secret-like fields.
class SafetyGateRuntime {
  const SafetyGateRuntime({required this.gate});

  final McpToolSafetyGate gate;

  Future<Object?> invoke({
    required String serverId,
    required McpToolSpec spec,
    required Map<String, Object?> arguments,
    required Duration timeout,
    FutureOr<bool> Function()? isCancelled,
    McpCancellationSignal? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw const McpToolException(McpToolFailure.cancelled);
    }
    if (isCancelled != null) {
      final cancelled = isCancelled();
      final bool wasCancelled;
      if (cancelled is Future<bool> && cancellation != null) {
        wasCancelled = await Future.any<bool>([
          cancelled,
          cancellation.whenCancelled.then<bool>((_) => true),
        ]);
      } else {
        wasCancelled = await cancelled;
      }
      if (wasCancelled) {
        throw const McpToolException(McpToolFailure.cancelled);
      }
    }
    if (cancellation?.isCancelled ?? false) {
      throw const McpToolException(McpToolFailure.cancelled);
    }

    final invocation = gate.execute(
      serverId: serverId,
      spec: spec,
      arguments: arguments,
      timeout: timeout,
    );

    // A cooperative signal makes cancellation observable while the gate waits
    // for permission or the tool. The gate's work may still finish remotely.
    final Object? result;
    if (cancellation == null) {
      result = await invocation;
    } else {
      result = await Future.any<Object?>([
        invocation,
        cancellation.whenCancelled.then<Object?>(
          (_) => throw const McpToolException(McpToolFailure.cancelled),
        ),
      ]);
      if (cancellation.isCancelled) {
        throw const McpToolException(McpToolFailure.cancelled);
      }
    }

    return _redactSecrets(result, <int>[10000]);
  }

  Object? _redactSecrets(Object? value, List<int> remaining) {
    remaining[0]--;
    if (remaining[0] < 0 || (value is String && value.length > 1048576)) {
      throw const McpToolException(McpToolFailure.resourceLimit);
    }
    if (value is Map) {
      final redacted = <Object?, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        redacted[entry.key] = _isSecretKey(key)
            ? '[REDACTED]'
            : _redactSecrets(entry.value, remaining);
      }
      return redacted;
    }
    if (value is List) {
      return value.map((item) => _redactSecrets(item, remaining)).toList();
    }
    return value;
  }

  bool _isSecretKey(String key) {
    return key.contains('token') ||
        key.contains('secret') ||
        key.contains('password') ||
        key.contains('private_key');
  }
}
