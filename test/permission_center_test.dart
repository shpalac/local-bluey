import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/permission_center.dart';
import 'package:local_bluey/services/safety_gate.dart';

void main() {
  test('grant then allows true and revoke immediately blocks action', () async {
    final center = PermissionCenter(
      safetyGate: SafetyGate(),
      now: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );

    center.grant('camera');
    expect(await center.allows('camera'), isTrue);

    center.revoke('camera');

    expect(await center.allows('camera'), isFalse);
  });

  test('expired grant does not silently allow action', () async {
    var nowMs = 2000;
    final center = PermissionCenter(
      safetyGate: SafetyGate(),
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
    );

    center.grant('microphone', expiry: const Duration(milliseconds: 500));

    expect(await center.allows('microphone'), isTrue);

    nowMs = 3000;

    expect(await center.allows('microphone'), isFalse);
  });
}
