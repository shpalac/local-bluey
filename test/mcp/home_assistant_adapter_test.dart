import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/home_assistant_adapter.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';

void main() {
  var transportCalls = 0;
  var allowed = true;
  var online = true;
  var local = true;
  var approved = true;
  var mcpAllowed = true;
  late HomeAssistantAdapter adapter;

  setUp(() {
    transportCalls = 0;
    allowed = true;
    online = true;
    local = true;
    approved = true;
    mcpAllowed = true;
    adapter = HomeAssistantAdapter(
      serverId: 'ha-local',
      allowedEntities: {'lock.front_door', 'light.desk'},
      enabled: true,
      isLocalEndpoint: () => local,
      isOnline: () => online,
      approve: (_, _) async => approved,
      gate: McpToolSafetyGate(
        isServerAllowed: (_) => allowed,
        requestPermission: (_, _) async => mcpAllowed,
        invoke: (_, _, _) async => true,
      ),
      transport: (_, _) async {
        transportCalls++;
        return 'ok';
      },
    );
  });

  Future<void> fails(
    Future<Object?> Function() action,
    HomeAssistantFailure failure,
  ) async {
    await expectLater(
      action(),
      throwsA(
        isA<HomeAssistantException>().having(
          (error) => error.reason,
          'reason',
          failure,
        ),
      ),
    );
    expect(transportCalls, 0);
  }

  test('dry run is default, requires approval, never dispatches', () async {
    expect(
      await adapter.call(
        entityId: 'light.desk',
        service: 'turn_on',
        timeout: const Duration(seconds: 1),
      ),
      {'dry_run': true},
    );
    expect(transportCalls, 0);
  });

  test('approved lock dispatches once', () async {
    expect(
      await adapter.call(
        entityId: 'lock.front_door',
        service: 'lock',
        dryRun: false,
        timeout: const Duration(seconds: 1),
      ),
      'ok',
    );
    expect(transportCalls, 1);
  });

  test('unknown entity and invalid service fail closed', () async {
    await fails(
      () => adapter.call(
        entityId: 'lock.unknown',
        service: 'unlock',
        dryRun: false,
        timeout: const Duration(seconds: 1),
      ),
      HomeAssistantFailure.invalidInput,
    );
    await fails(
      () => adapter.call(
        entityId: 'light.desk',
        service: 'execute',
        dryRun: false,
        timeout: const Duration(seconds: 1),
      ),
      HomeAssistantFailure.invalidInput,
    );
  });

  test('denied permission and physical approval block transport', () async {
    mcpAllowed = false;
    await fails(
      () => adapter.call(
        entityId: 'lock.front_door',
        service: 'unlock',
        dryRun: false,
        timeout: const Duration(seconds: 1),
      ),
      HomeAssistantFailure.denied,
    );
    mcpAllowed = true;
    approved = false;
    await fails(
      () => adapter.call(
        entityId: 'lock.front_door',
        service: 'unlock',
        dryRun: false,
        timeout: const Duration(seconds: 1),
      ),
      HomeAssistantFailure.denied,
    );
  });

  test('non-local and disabled adapters deny without transport', () async {
    local = false;
    await fails(
      () => adapter.call(
        entityId: 'light.desk',
        service: 'turn_on',
        dryRun: false,
        timeout: const Duration(seconds: 1),
      ),
      HomeAssistantFailure.denied,
    );
  });

  test('offline fails closed', () async {
    online = false;
    await fails(
      () => adapter.call(
        entityId: 'light.desk',
        service: 'turn_on',
        dryRun: false,
        timeout: const Duration(seconds: 1),
      ),
      HomeAssistantFailure.offline,
    );
  });

  test('cancellation and restart never inherit an approval', () async {
    adapter.cancel();
    await fails(
      () => adapter.call(
        entityId: 'light.desk',
        service: 'turn_on',
        dryRun: false,
        timeout: const Duration(seconds: 1),
      ),
      HomeAssistantFailure.cancelled,
    );
    adapter.restart();
    approved = false;
    await fails(
      () => adapter.call(
        entityId: 'light.desk',
        service: 'turn_on',
        dryRun: false,
        timeout: const Duration(seconds: 1),
      ),
      HomeAssistantFailure.denied,
    );
  });

  test('timeout denies before transport when approval stalls', () async {
    final waiting = Completer<bool>();
    adapter = HomeAssistantAdapter(
      serverId: 'ha-local',
      allowedEntities: {'lock.front_door'},
      enabled: true,
      isLocalEndpoint: () => true,
      isOnline: () => true,
      approve: (_, _) => waiting.future,
      gate: McpToolSafetyGate(
        isServerAllowed: (_) => true,
        requestPermission: (_, _) async => true,
        invoke: (_, _, _) async => true,
      ),
      transport: (_, _) async {
        transportCalls++;
        return null;
      },
    );
    await fails(
      () => adapter.call(
        entityId: 'lock.front_door',
        service: 'unlock',
        dryRun: false,
        timeout: const Duration(milliseconds: 10),
      ),
      HomeAssistantFailure.timeout,
    );
  });
  test('revoked server permission during lock approval blocks transport', () async {
    final enteredApproval = Completer<void>();
    final approval = Completer<bool>();
    adapter = HomeAssistantAdapter(
      serverId: 'ha-local',
      allowedEntities: {'lock.front_door'},
      enabled: true,
      isLocalEndpoint: () => local,
      isOnline: () => online,
      approve: (_, _) {
        enteredApproval.complete();
        return approval.future;
      },
      gate: McpToolSafetyGate(
        isServerAllowed: (_) => allowed,
        requestPermission: (_, _) async => true,
        invoke: (_, _, _) async => true,
      ),
      transport: (_, _) async {
        transportCalls++;
        return 'ok';
      },
    );

    final pending = adapter.call(
      entityId: 'lock.front_door',
      service: 'unlock',
      dryRun: false,
      timeout: const Duration(seconds: 1),
    );
    await enteredApproval.future;
    allowed = false;
    approval.complete(true);

    await expectLater(
      pending,
      throwsA(isA<HomeAssistantException>().having(
        (error) => error.reason,
        'reason',
        HomeAssistantFailure.denied,
      )),
    );
    expect(transportCalls, 0);
  });

  test('offline transition during MCP gate blocks transport', () async {
    final enteredGate = Completer<void>();
    final gateResult = Completer<Object?>();
    adapter = HomeAssistantAdapter(
      serverId: 'ha-local',
      allowedEntities: {'light.desk'},
      enabled: true,
      isLocalEndpoint: () => local,
      isOnline: () => online,
      approve: (_, _) async => true,
      gate: McpToolSafetyGate(
        isServerAllowed: (_) => allowed,
        requestPermission: (_, _) async => true,
        invoke: (_, _, _) {
          enteredGate.complete();
          return gateResult.future;
        },
      ),
      transport: (_, _) async {
        transportCalls++;
        return 'ok';
      },
    );

    final pending = adapter.call(
      entityId: 'light.desk',
      service: 'turn_on',
      dryRun: false,
      timeout: const Duration(seconds: 1),
    );
    await enteredGate.future;
    online = false;
    gateResult.complete(true);

    await expectLater(
      pending,
      throwsA(isA<HomeAssistantException>().having(
        (error) => error.reason,
        'reason',
        HomeAssistantFailure.offline,
      )),
    );
    expect(transportCalls, 0);
  });

}
