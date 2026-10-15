/// Fail-closed validation boundary for untrusted MCP tool metadata.
///
/// This module deliberately does not launch processes or send network requests.
library;

import 'dart:async';

enum McpToolFailure {
  invalidSchema,
  invalidArguments,
  denied,
  offline,
  timeout,
  cancelled,
}

class McpToolException implements Exception {
  const McpToolException(this.reason);

  final McpToolFailure reason;
}

class McpToolSpec {
  McpToolSpec({
    required this.name,
    required this.description,
    required this.inputSchema,
  }) {
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_.-]{0,127}$').hasMatch(name) ||
        description.length > 8192 ||
        inputSchema['type'] != 'object' ||
        inputSchema['properties'] is! Map ||
        (inputSchema['required'] != null && inputSchema['required'] is! List)) {
      throw const McpToolException(McpToolFailure.invalidSchema);
    }
  }

  final String name;

  /// Untrusted display-only text; never interpreted as an instruction.
  final String description;
  final Map<String, Object?> inputSchema;

  void validateArguments(Map<String, Object?> arguments) {
    final properties = inputSchema['properties'] as Map;
    final required = (inputSchema['required'] as List?) ?? const [];
    if (required.any((key) => key is! String || !properties.containsKey(key)) ||
        required.any((key) => !arguments.containsKey(key))) {
      throw const McpToolException(McpToolFailure.invalidArguments);
    }

    for (final entry in arguments.entries) {
      final schema = properties[entry.key];
      if (schema is! Map) {
        throw const McpToolException(McpToolFailure.invalidArguments);
      }

      final valid = switch (schema['type']) {
        'string' => entry.value is String,
        'integer' => entry.value is int,
        'number' => entry.value is num,
        'boolean' => entry.value is bool,
        'object' => entry.value is Map,
        'array' => entry.value is List,
        'null' => entry.value == null,
        _ => false,
      };

      if (!valid) {
        throw const McpToolException(McpToolFailure.invalidArguments);
      }
    }
  }
}

typedef McpPermissionCheck = Future<bool> Function(
  String serverId,
  String toolName,
);
typedef McpToolInvoker = Future<Object?> Function(
  String serverId,
  String toolName,
  Map<String, Object?> arguments,
);

/// Authorization is checked for every invocation, never inferred from metadata.
class McpToolSafetyGate {
  const McpToolSafetyGate({
    required this.isServerAllowed,
    required this.requestPermission,
    required this.invoke,
  });

  final bool Function(String serverId) isServerAllowed;
  final McpPermissionCheck requestPermission;
  final McpToolInvoker invoke;

  Future<Object?> execute({
    required String serverId,
    required McpToolSpec spec,
    required Map<String, Object?> arguments,
    required Duration timeout,
  }) async {
    if (!isServerAllowed(serverId)) {
      throw const McpToolException(McpToolFailure.denied);
    }

    spec.validateArguments(arguments);

    try {
      // A stalled approval must not keep an MCP invocation pending forever.
      final approved = await requestPermission(serverId, spec.name).timeout(timeout);
      if (!approved) {
        throw const McpToolException(McpToolFailure.denied);
      }
      return await invoke(serverId, spec.name, arguments).timeout(timeout);
    } on TimeoutException {
      throw const McpToolException(McpToolFailure.timeout);
    }
  }
}
