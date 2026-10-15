import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/permission_center.dart';
import 'package:local_bluey/services/safety_gate.dart';

class PendingPermissionGate extends SafetyGate {
  PendingPermissionGate(this.authorization);

  final Future<bool> authorization;

  @override
  Future<bool> authorize(String tool, Map<String, dynamic> arguments) =>
      authorization;
}

void main() {
  test('in-flight revocation denies the pending authorization', () async {
    final response = Completer<bool>();
    final center = PermissionCenter(
      safetyGate: PendingPermissionGate(response.future),
    );
    center.grant('camera');

    final pending = center.allows('camera');
    center.revoke('camera');
    response.complete(true);

    expect(await pending, isFalse);
  });

  test('authorization failure propagates without silent fallback', () async {
    final response = Completer<bool>();
    final center = PermissionCenter(
      safetyGate: PendingPermissionGate(response.future),
    );
    center.grant('camera');

    final pending = center.allows('camera');
    response.completeError(StateError('authorization unavailable'));

    await expectLater(pending, throwsStateError);
  });

  test('expired grant while approval is pending denies authorization', () async {
    var nowMs = 1000;
    final response = Completer<bool>();
    final center = PermissionCenter(
      safetyGate: PendingPermissionGate(response.future),
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
    );
    center.grant('camera', expiry: const Duration(milliseconds: 500));

    final pending = center.allows('camera');
    nowMs = 1600;
    response.complete(true);

    expect(await pending, isFalse);
  });

  test('replaced grant cannot authorize an older pending action', () async {
    final response = Completer<bool>();
    final center = PermissionCenter(
      safetyGate: PendingPermissionGate(response.future),
    );
    center.grant('camera');

    final pending = center.allows('camera');
    center.grant('camera');
    response.complete(true);

    expect(await pending, isFalse);
  });
}
