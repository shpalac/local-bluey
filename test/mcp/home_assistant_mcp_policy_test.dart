import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/home_assistant_mcp_policy.dart';

void main() {
  test('approved local allowed lock passes policy', () {
    final policy = HomeAssistantMcpPolicy(allowedEntities: {'lock.front_door'});

    final result = policy.validate(
      entityId: 'lock.front_door',
      service: 'lock',
      localEndpoint: true,
      enabled: true,
    );

    expect(result.allowed, isTrue);
    expect(result.reason, HomeAssistantPolicyFailure.none);
  });

  test('unknown entities fail closed', () {
    final policy = HomeAssistantMcpPolicy(allowedEntities: {'lock.front_door'});

    final result = policy.validate(
      entityId: 'lock.back_door',
      service: 'lock',
      localEndpoint: true,
      enabled: true,
    );

    expect(result.allowed, isFalse);
    expect(result.reason, HomeAssistantPolicyFailure.invalid);
  });

  test('remote endpoint and disabled adapter are denied', () {
    final policy = HomeAssistantMcpPolicy(allowedEntities: {'light.desk'});

    expect(
      policy
          .validate(
            entityId: 'light.desk',
            service: 'turn_on',
            localEndpoint: false,
            enabled: true,
          )
          .reason,
      HomeAssistantPolicyFailure.denied,
    );

    expect(
      policy
          .validate(
            entityId: 'light.desk',
            service: 'turn_on',
            localEndpoint: true,
            enabled: false,
          )
          .reason,
      HomeAssistantPolicyFailure.denied,
    );
  });
}
