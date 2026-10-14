import 'dart:async';

import 'mcp_tool_safety_gate.dart';

/// Production boundary helpers for MCP execution.
///
/// Keeps approval, redaction, and lifecycle handling outside untrusted tool
/// metadata. Native permission checks can be supplied by platform adapters.
class SafetyGateRuntime {
  const SafetyGateRuntime({required McpToolSafetyGate gate}) : _gate = gate;

  final McpToolSafetyGate _gate;

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

    final result = await _gate.execute(
      serverId: serverId,
      spec: spec,
      arguments: arguments,
      timeout: timeout,
    );

    if (result is Map) {
      return _redactSecrets(result);
    }

    return result;
  }

  Map<Object?, Object?> _redactSecrets(Map<Object?, Object?> input) {
    final redacted = <Object?, Object?>{};
    for (final entry in input.entries) {
      final key = entry.key.toString().toLowerCase();
      redacted[entry.key] = _isSecretKey(key) ? '[REDACTED]' : entry.value;
    }
    return redacted;
  }

  bool _isSecretKey(String key) {
    return key.contains('token') ||
        key.contains('secret') ||
        key.contains('password') ||
        key.contains('private_key');
  }
}
