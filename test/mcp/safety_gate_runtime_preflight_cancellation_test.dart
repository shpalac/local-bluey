import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';
import 'package:local_bluey/mcp/safety_gate_runtime.dart';

void main() {
  test('runtime cancellation interrupts pending async precheck', () async {
    final precheckStarted = Completer<void>();
    final finishPrecheck = Completer<bool>();
    final cancellation = McpCancellationSignal();
    var permissionRequested = false;
    var toolInvoked = false;
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async {
        permissionRequested = true;
        return true;
      },
      invoke: (_, _, _) async {
        toolInvoked = true;
        return 'unexpected';
      },
    );

    final invocation = SafetyGateRuntime(gate: gate).invoke(
      serverId: 'fake',
      spec: McpToolSpec(
        name: 'read',
        description: 'read value',
        inputSchema: const {'type': 'object', 'properties': {}},
      ),
      arguments: const {},
      timeout: const Duration(seconds: 1),
      cancellation: cancellation,
      isCancelled: () {
        precheckStarted.complete();
        return finishPrecheck.future;
      },
    );

    await precheckStarted.future;
    cancellation.cancel();

    await expectLater(
      invocation,
      throwsA(
        isA<McpToolException>().having(
          (error) => error.reason,
          'reason',
          McpToolFailure.cancelled,
        ),
      ),
    );
    expect(permissionRequested, isFalse);
    expect(toolInvoked, isFalse);
    finishPrecheck.complete(false);
  });
}
