import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/home_assistant_adapter.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';

void main() {
  test('ac1 dry run never invokes MCP action or HA transport', () async {
    var mcpActions = 0;
    var haActions = 0;
    final adapter = HomeAssistantAdapter(
      serverId: 'local',
      allowedEntities: {'lock.front_door'},
      enabled: true,
      isLocalEndpoint: () => true,
      isOnline: () => true,
      approve: (_, _) async => true,
      gate: McpToolSafetyGate(
        isServerAllowed: (_) => true,
        requestPermission: (_, _) async => true,
        invoke: (_, _, _) async {
          mcpActions++;
          return true;
        },
      ),
      transport: (_, _) async {
        haActions++;
        return 'unexpected';
      },
    );

    expect(
      await adapter.call(
        entityId: 'lock.front_door',
        service: 'lock',
        timeout: const Duration(seconds: 1),
      ),
      {'dry_run': true},
    );
    expect(mcpActions, 0);
    expect(haActions, 0);
  });

  test('ac2 approved live action executes exactly one transport', () async {
    var mcpActions = 0;
    var haActions = 0;
    final adapter = HomeAssistantAdapter(
      serverId: 'local',
      allowedEntities: {'light.desk'},
      enabled: true,
      isLocalEndpoint: () => true,
      isOnline: () => true,
      approve: (_, _) async => true,
      gate: McpToolSafetyGate(
        isServerAllowed: (_) => true,
        requestPermission: (_, _) async => true,
        invoke: (_, _, _) async {
          mcpActions++;
          return 'untrusted';
        },
      ),
      transport: (_, _) async {
        haActions++;
        return 'ok';
      },
    );

    expect(
      await adapter.call(
        entityId: 'light.desk',
        service: 'turn_on',
        dryRun: false,
        timeout: const Duration(seconds: 1),
      ),
      'ok',
    );
    expect(mcpActions, 0);
    expect(haActions, 1);
  });
}
