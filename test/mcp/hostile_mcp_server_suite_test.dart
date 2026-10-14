import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';
import 'package:local_bluey/mcp/safety_gate_runtime.dart';

McpToolSpec _spec() => McpToolSpec(
      name: 'hostile_read',
      description: 'untrusted server output',
      inputSchema: const {'type': 'object'},
    );

void main() {
  test('hostile nested output redacts secrets deterministically', () async {
    final runtime = SafetyGateRuntime(
      gate: McpToolSafetyGate(
        isServerAllowed: (_) => true,
        requestPermission: (_, _) async => true,
        invoke: (_, _, _) async => {
          'result': {
            'token': 'secret-value',
            'items': [
              {'password': 'hidden'},
              {'safe': 'value'},
            ],
          },
        },
      ),
    );

    expect(
      await runtime.invoke(
        serverId: 'hostile',
        spec: _spec(),
        arguments: const {},
        timeout: const Duration(seconds: 1),
      ),
      {
        'result': {
          'token': '[REDACTED]',
          'items': [
            {'password': '[REDACTED]'},
            {'safe': 'value'},
          ],
        },
      },
    );
  });

  test('hostile server denial returns explicit policy error', () async {
    final runtime = SafetyGateRuntime(
      gate: McpToolSafetyGate(
        isServerAllowed: (_) => false,
        requestPermission: (_, _) async => true,
        invoke: (_, _, _) async => 'must not run',
      ),
    );

    await expectLater(
      runtime.invoke(
        serverId: 'blocked',
        spec: _spec(),
        arguments: const {},
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<McpToolException>()),
    );
  });
}
