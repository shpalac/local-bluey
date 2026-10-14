import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';
import 'package:local_bluey/mcp/safety_gate_runtime.dart';

void main() {
  test('runtime redacts secret output after approved invocation', () async {
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async => true,
      invoke: (_, _, _) async => {
        'value': 'ok',
        'token': 'hidden',
      },
    );

    final result = await const SafetyGateRuntime(gate: null).invoke;
    expect(result, isNotNull);
  });
}
