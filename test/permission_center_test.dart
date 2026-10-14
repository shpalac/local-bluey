import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/permission_center.dart';

void main() {
  test('grant then allows true and revoke immediately blocks action', () {
    final center = PermissionCenter(
      now: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );

    center.grant('camera');
    expect(center.allows('camera'), isTrue);

    center.revoke('camera');

    expect(center.allows('camera'), isFalse);
  });

  test('expired grant does not silently allow action', () {
    final center = PermissionCenter(
      now: () => DateTime.fromMillisecondsSinceEpoch(2000),
    );

    center.grant('microphone', expiry: const Duration(milliseconds: 500));

    expect(center.allows('microphone'), isFalse);
  });
}
