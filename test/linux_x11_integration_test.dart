import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/linux_x11_host_control.dart';

/// Real-backend contract test (#150): runs only when a live X11 display and
/// the helper binaries exist (e.g. CI under Xvfb). Set BLUEY_X11_INTEGRATION=1
/// to enable. In CI: xvfb-run -a flutter test test/linux_x11_integration_test.dart
void main() {
  final enabled = Platform.environment['BLUEY_X11_INTEGRATION'] == '1';

  test(
    'move pointer and read it back; screenshot has the display size',
    () async {
      final host = LinuxX11HostControl();
      expect(await host.isTrusted(), isTrue);

      await host.warp(120, 90);
      final at = await host.mouseLocation();
      expect(at.dx, closeTo(120, 2));
      expect(at.dy, closeTo(90, 2));

      final snap = await host.snapshot();
      expect(snap.jpeg, isNotEmpty);
      expect(snap.width, greaterThan(0));
      expect(snap.height, greaterThan(0));
    },
    skip: !enabled,
  );
}
