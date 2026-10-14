import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';
import 'package:local_bluey/mcp/safety_gate_runtime.dart';

McpToolSpec _spec() => McpToolSpec(
  name: 'read',
  description: 'read value',
  inputSchema: {'type': 'object', 'properties': {}},
);

Future<Object?> _invoke(
  McpToolSafetyGate gate, {
  McpCancellationSignal? cancellation,
  FutureOr<bool> Function()? isCancelled,
}) {
  return SafetyGateRuntime(gate: gate).invoke(
    serverId: 'local',
    spec: _spec(),
    arguments: const {},
    timeout: const Duration(seconds: 1),
    cancellation: cancellation,
    isCancelled: isCancelled,
  );
}

void main() {
  test('runtime redacts secret output after approved invocation', () async {
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async => true,
      invoke: (_, _, _) async => {'value': 'ok', 'token': 'hidden'},
    );

    expect(await _invoke(gate), {'value': 'ok', 'token': '[REDACTED]'});
  });

  test('runtime recursively redacts nested maps and lists', () async {
    final original = {
      'items': [
        {
          'metadata': {
            'apiToken': 'secret-token',
            'safe': 'visible',
            'children': [
              {'password': 'pass', 'value': 42},
              {'private_key': 'key', 'secretHint': 'hint'},
            ],
          },
        },
      ],
      'safe': true,
    };
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async => true,
      invoke: (_, _, _) async => original,
    );

    expect(await _invoke(gate), {
      'items': [
        {
          'metadata': {
            'apiToken': '[REDACTED]',
            'safe': 'visible',
            'children': [
              {'password': '[REDACTED]', 'value': 42},
              {'private_key': '[REDACTED]', 'secretHint': '[REDACTED]'},
            ],
          },
        },
      ],
      'safe': true,
    });
    expect(
      (original['items'] as List).first.toString(),
      contains('secret-token'),
    );
  });

  test('runtime redacts top-level list results', () async {
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async => true,
      invoke: (_, _, _) async => [
        {'accessToken': 'raw'},
        [
          {'password': 'raw'},
        ],
      ],
    );

    expect(await _invoke(gate), [
      {'accessToken': '[REDACTED]'},
      [
        {'password': '[REDACTED]'},
      ],
    ]);
  });

  test('runtime rejects cancelled calls before execution', () async {
    var invoked = false;
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async => true,
      invoke: (_, _, _) async {
        invoked = true;
        return 'unexpected';
      },
    );

    await expectLater(
      _invoke(gate, isCancelled: () => true),
      throwsA(
        isA<McpToolException>().having(
          (e) => e.reason,
          'reason',
          McpToolFailure.cancelled,
        ),
      ),
    );
    expect(invoked, isFalse);
  });

  test('runtime cancels during an invocation with controllable fake', () async {
    final started = Completer<void>();
    final completeTool = Completer<Object?>();
    final cancellation = McpCancellationSignal();
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async => true,
      invoke: (_, _, _) {
        started.complete();
        return completeTool.future;
      },
    );

    final result = _invoke(gate, cancellation: cancellation);
    await started.future;
    cancellation.cancel();

    await expectLater(
      result,
      throwsA(
        isA<McpToolException>().having(
          (error) => error.reason,
          'reason',
          McpToolFailure.cancelled,
        ),
      ),
    );
    completeTool.complete({'token': 'not returned'});
  });

  test('runtime preserves underlying permission denial', () async {
    var invoked = false;
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async => false,
      invoke: (_, _, _) async {
        invoked = true;
        return 'unexpected';
      },
    );

    await expectLater(
      _invoke(gate),
      throwsA(
        isA<McpToolException>().having(
          (error) => error.reason,
          'reason',
          McpToolFailure.denied,
        ),
      ),
    );
    expect(invoked, isFalse);
  });

  test('runtime preserves underlying approved result', () async {
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async => true,
      invoke: (_, _, _) async => 'approved',
    );

    expect(await _invoke(gate), 'approved');
  });
}
