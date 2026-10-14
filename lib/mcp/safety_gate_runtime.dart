import 'dart:async';

import 'mcp_tool_safety_gate.dart';

/// Production boundary helpers for MCP execution.
class SafetyGateRuntime {
  const SafetyGateRuntime({required this.gate});

  final McpToolSafetyGate gate;

  Future<Object?> invoke({
    required String serverId,
    required McpToolSpec spec,
    required Map<String, Object?> arguments,
    required Duration timeout,
    FutureOr<bool> Function()? isCancelled,
  }) async {
    if (isCancelled != null && await isCancelled()) {
      throw const McpToolException(McpToolFailure.cancelled);
    }

    final result = await gate.execute(
      serverId: serverId,
      spec: spec,
      arguments: arguments,
      timeout: timeout,
    );

    return _redactValue(result);
  }

  Object? _redactValue(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key: _isSecretKey(entry.key.toString())
              ? '[REDACTED]'
              : _redactValue(entry.value),
      };
    }

    if (value is List) {
      return value.map(_redactValue).toList(growable: false);
    }

    return value;
  }

  bool _isSecretKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('password') ||
        normalized.contains('private_key');
  }
}
