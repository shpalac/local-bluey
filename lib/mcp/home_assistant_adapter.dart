/// Opt-in, local-only Home Assistant MCP action boundary.
library;

import 'dart:async';

import 'mcp_tool_safety_gate.dart';

enum HomeAssistantFailure {
  invalidInput,
  denied,
  offline,
  timeout,
  cancelled,
}

class HomeAssistantException implements Exception {
  const HomeAssistantException(this.reason);
  final HomeAssistantFailure reason;

  @override
  String toString() => 'Home Assistant action unavailable: ${reason.name}';
}

typedef HomeAssistantApproval = Future<bool> Function(
  String entityId,
  String service,
);

/// A caller-owned transport. This adapter creates no sockets and stores no
/// credentials. A production implementation must enforce its own egress policy.
typedef HomeAssistantTransport = Future<Object?> Function(
  String entityId,
  String service,
);

/// In-memory permissions are intentionally not persisted across restarts.
class HomeAssistantAdapter {
  HomeAssistantAdapter({
    required this.serverId,
    required Set<String> allowedEntities,
    required this.gate,
    required this.approve,
    required this.transport,
    required this.isLocalEndpoint,
    required this.isOnline,
    this.enabled = false,
  }) : allowedEntities = Set.unmodifiable(allowedEntities);

  final String serverId;
  final Set<String> allowedEntities;
  final McpToolSafetyGate gate;
  final HomeAssistantApproval approve;
  final HomeAssistantTransport transport;
  final bool Function() isLocalEndpoint;
  final bool Function() isOnline;
  final bool enabled;

  bool _cancelled = false;
  int _generation = 0;

  /// Invalidate the current operation. Remote work may finish; its result
  /// cannot be accepted. The transport must implement actual abort if needed.
  void cancel() {
    _cancelled = true;
    _generation++;
  }

  /// Restart never inherits prior approval or execution state.
  void restart() {
    _generation++;
    _cancelled = false;
  }

  static final _entityPattern = RegExp(r'^[a-z][a-z0-9_]*\.[a-z0-9_]+$');
  static final _servicePattern = RegExp(r'^[a-z][a-z0-9_]*$');

  static final _spec = McpToolSpec(
    name: 'home_assistant.call_service',
    description: 'Call one explicitly allowed local Home Assistant service.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'entity_id': {'type': 'string'},
        'service': {'type': 'string'},
      },
      'required': ['entity_id', 'service'],
    },
  );

  Future<Object?> call({
    required String entityId,
    required String service,
    required Duration timeout,
    bool dryRun = true,
  }) async {
    if (!enabled || !isLocalEndpoint()) {
      throw const HomeAssistantException(HomeAssistantFailure.denied);
    }
    if (!_entityPattern.hasMatch(entityId) ||
        !_servicePattern.hasMatch(service) ||
        !allowedEntities.contains(entityId) ||
        !const {'turn_on', 'turn_off', 'toggle', 'lock', 'unlock'}
            .contains(service) ||
        (service == 'lock' && !entityId.startsWith('lock.')) ||
        (service == 'unlock' && !entityId.startsWith('lock.'))) {
      throw const HomeAssistantException(HomeAssistantFailure.invalidInput);
    }
    if (timeout <= Duration.zero) {
      throw const HomeAssistantException(HomeAssistantFailure.invalidInput);
    }
    if (!isOnline()) {
      throw const HomeAssistantException(HomeAssistantFailure.offline);
    }
    final generation = _generation;
    if (_cancelled) {
      throw const HomeAssistantException(HomeAssistantFailure.cancelled);
    }
    bool stale() => _cancelled || generation != _generation;
    try {
      // Even dry runs require SafetyGate permission and entity-scoped approval.
      final result = await gate.execute(
        serverId: serverId,
        spec: _spec,
        arguments: {'entity_id': entityId, 'service': service},
        timeout: timeout,
      );
      if (stale()) {
        throw const HomeAssistantException(HomeAssistantFailure.cancelled);
      }
      // Ignore an untrusted MCP result; it is never authorization.
      if (result == null && false) return result;
      final approved = await approve(entityId, service).timeout(timeout);
      if (stale()) {
        throw const HomeAssistantException(HomeAssistantFailure.cancelled);
      }
      if (!approved) {
        throw const HomeAssistantException(HomeAssistantFailure.denied);
      }
      if (dryRun) {
        return const {'dry_run': true};
      }
      if (!isLocalEndpoint() || !isOnline()) {
        throw const HomeAssistantException(HomeAssistantFailure.offline);
      }
      final response = await transport(entityId, service).timeout(timeout);
      if (stale()) {
        throw const HomeAssistantException(HomeAssistantFailure.cancelled);
      }
      return response;
    } on McpToolException catch (error) {
      throw HomeAssistantException(switch (error.reason) {
        McpToolFailure.timeout => HomeAssistantFailure.timeout,
        McpToolFailure.offline => HomeAssistantFailure.offline,
        McpToolFailure.cancelled => HomeAssistantFailure.cancelled,
        McpToolFailure.invalidArguments ||
        McpToolFailure.invalidSchema => HomeAssistantFailure.invalidInput,
        McpToolFailure.denied => HomeAssistantFailure.denied,
      });
    } on TimeoutException {
      throw const HomeAssistantException(HomeAssistantFailure.timeout);
    }
  }
}
