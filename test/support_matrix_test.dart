import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/support_matrix.dart';

void main() {
  test('macOS is the host with full capabilities', () {
    final p = SupportMatrix.profile(operatingSystem: 'macos');
    expect(p.role, AppRole.host);
    expect(p.supports(SupportMatrix.hostControl), isTrue);
    expect(p.supports(SupportMatrix.windowManagement), isTrue);
  });

  test('iOS and Android are phone clients', () {
    expect(SupportMatrix.resolveRole(operatingSystem: 'ios'),
        AppRole.phoneClient);
    expect(SupportMatrix.resolveRole(operatingSystem: 'android'),
        AppRole.phoneClient);
  });

  test('unknown platforms are unsupported, never silently hosts', () {
    expect(SupportMatrix.resolveRole(operatingSystem: 'fuchsia'),
        AppRole.unsupported);
  });

  test('device names match the pair-facing labels', () {
    expect(SupportMatrix.deviceName(operatingSystem: 'ios'), 'iPhone');
    expect(SupportMatrix.deviceName(operatingSystem: 'macos'), 'Mac');
    expect(SupportMatrix.deviceName(operatingSystem: 'linux'), 'Device');
  });
}
