import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';
import 'package:local_bluey/mcp/safety_gate_runtime.dart';

McpToolSpec _spec() => McpToolSpec(
  name: 'read',
  description: 'read value',
  inputSchema: {'type': 'object', 'properties': {}},
);

void main() {
  test('runtime redacts secret output after approved invocation', () async {
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async => true,
      invoke: (_, _, _) async => {'value': 'ok', 'token': 'hidden'},
    );

    final result = await SafetyGateRuntime(gate: gate).invoke(
      serverId: 'local',
      spec: _spec(),
      arguments: const {},
      timeout: const Duration(seconds: 1),
    );

    expect(result, {'value': 'ok', 'token': '[REDACTED]'});
  });

  test('runtime rejects cancelled calls before execution', () async {
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async => true,
      invoke: (_, _, _) async => 'unexpected',
    );

    await expectLater(
      SafetyGateRuntime(gate: gate).invoke(
        serverId: 'local',
        spec: _spec(),
        arguments: const {},
        timeout: const Duration(seconds: 1),
        isCancelled: () => true,
      ),
      throwsA(
        isA<McpToolException>().having(
          (e) => e.reason,
          'reason',
          McpToolFailure.cancelled,
        ),
      ),
    );
  });
}
