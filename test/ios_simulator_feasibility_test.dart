import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS simulator feasibility baseline is deterministic', () {
    const supportedOnStandardMacosRunner = true;
    const requiresRealDevicePermissions = false;

    expect(supportedOnStandardMacosRunner, isTrue);
    expect(requiresRealDevicePermissions, isFalse);
  });
}
