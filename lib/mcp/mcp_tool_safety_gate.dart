import 'dart:async';

/// Fail-closed validation boundary for untrusted MCP tool metadata.
///
/// This module deliberately does not launch processes or send network requests.
library;

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
        (inputSchema['required'] != null &&
            inputSchema['required'] is! List)) {
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
      final type = schema['type'];
      final value = entry.value;
      final valid = switch (type) {
        'string' => value is String,
        'integer' => value is int,
        'number' => value is num,
        'boolean' => value is bool,
        'object' => value is Map,
        'array' => value is List,
        'null' => value == null,
        _ => false,
      };
      if (!valid) {
        throw const McpToolException(McpToolFailure.invalidArguments);
      }
    }
  }
}

typedef McpPermissionCheck = Future<bool> Function(String serverId, String toolName);
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
    if (!await requestPermission(serverId, spec.name)) {
      throw const McpToolException(McpToolFailure.denied);
    }
    try {
      return await invoke(serverId, spec.name, arguments).timeout(timeout);
    } on TimeoutException {
      throw const McpToolException(McpToolFailure.timeout);
    }
  }
}
