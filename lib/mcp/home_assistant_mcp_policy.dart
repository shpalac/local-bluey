/// Deterministic policy boundary for Home Assistant MCP adapters.
///
/// This module intentionally does not perform network I/O. Callers must provide
/// transport only after this policy approves the request.
class HomeAssistantMcpPolicy {
  HomeAssistantMcpPolicy({required Set<String> allowedEntities})
    : _allowedEntities = Set.unmodifiable(allowedEntities);

  final Set<String> _allowedEntities;

  static const _services = <String>{
    'turn_on',
    'turn_off',
    'toggle',
    'lock',
    'unlock',
  };

  HomeAssistantPolicyResult validate({
    required String entityId,
    required String service,
    required bool localEndpoint,
    required bool enabled,
  }) {
    if (!enabled || !localEndpoint) {
      return const HomeAssistantPolicyResult.denied();
    }
    if (!_allowedEntities.contains(entityId) || !_services.contains(service)) {
      return const HomeAssistantPolicyResult.invalid();
    }
    if ((service == 'lock' || service == 'unlock') &&
        !entityId.startsWith('lock.')) {
      return const HomeAssistantPolicyResult.invalid();
    }
    return const HomeAssistantPolicyResult.approved();
  }
}

class HomeAssistantPolicyResult {
  const HomeAssistantPolicyResult._(this.allowed, this.reason);

  const HomeAssistantPolicyResult.approved()
    : this._(true, HomeAssistantPolicyFailure.none);

  const HomeAssistantPolicyResult.denied()
    : this._(false, HomeAssistantPolicyFailure.denied);

  const HomeAssistantPolicyResult.invalid()
    : this._(false, HomeAssistantPolicyFailure.invalid);

  final bool allowed;
  final HomeAssistantPolicyFailure reason;
}

enum HomeAssistantPolicyFailure { none, denied, invalid }
