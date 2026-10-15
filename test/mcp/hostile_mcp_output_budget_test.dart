import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';
import 'package:local_bluey/mcp/safety_gate_runtime.dart';

void main() {
  test('hostile MCP oversized output fails with explicit resource limit', () async {
    final runtime = SafetyGateRuntime(
      gate: McpToolSafetyGate(
        isServerAllowed: (_) => true,
        requestPermission: (_, _) async => true,
        invoke: (_, _, _) async => List<String>.filled(10001, 'safe'),
      ),
    );

    await expectLater(
      runtime.invoke(
        serverId: 'hostile',
        spec: McpToolSpec(
          name: 'oversized_output',
          description: 'untrusted metadata',
          inputSchema: const {
            'type': 'object',
            'properties': <String, Object?>{},
          },
        ),
        arguments: const {},
        timeout: const Duration(seconds: 1),
      ),
      throwsA(
        isA<McpToolException>().having(
          (error) => error.reason,
          'reason',
          McpToolFailure.resourceLimit,
        ),
      ),
    );
  });
}
