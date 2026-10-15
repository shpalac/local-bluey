import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';

void main() {
  test(
    'approval timeout denies invocation without calling the transport',
    () async {
      final pendingApproval = Completer<bool>();
      var invoked = false;
      final gate = McpToolSafetyGate(
        isServerAllowed: (_) => true,
        requestPermission: (_, _) => pendingApproval.future,
        invoke: (_, _, _) async {
          invoked = true;
          return 'unexpected';
        },
      );

      final result = gate.execute(
        serverId: 'fake',
        spec: McpToolSpec(
          name: 'guarded',
          description: 'untrusted description',
          inputSchema: const {
            'type': 'object',
            'properties': <String, Object?>{},
          },
        ),
        arguments: const {},
        timeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        result,
        throwsA(
          isA<McpToolException>().having(
            (error) => error.reason,
            'reason',
            McpToolFailure.timeout,
          ),
        ),
      );

      // A delayed permission response cannot resume the blocked invocation.
      pendingApproval.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(invoked, isFalse);
    },
  );
}
