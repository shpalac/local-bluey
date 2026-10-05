import 'dart:io';

import 'dart:ui' show Offset;

import 'linux_x11_host_control.dart';
import 'native_control.dart';
import 'tool_executor.dart';

/// Host control: screen capture, input and accessibility on the machine
/// Bluey runs on. Everything platform-specific lives behind this interface
/// so Linux/Windows hosts can plug in without touching the brain (#52).
abstract class HostControl implements NativeControlClient {
  Future<bool> isTrusted();
  Future<void> askPermission();
  Future<void> openAccessibilitySettings();

  /// The host for the current platform. Pass [operatingSystem] and
  /// [environment] in tests.
  static HostControl forPlatform({
    String? operatingSystem,
    Map<String, String>? environment,
  }) {
    final os = operatingSystem ?? Platform.operatingSystem;
    if (os == 'macos') return const MacHostControl();
    if (os == 'linux') {
      final env = environment ?? Platform.environment;
      final display = env['DISPLAY'] ?? '';
      final session = (env['XDG_SESSION_TYPE'] ?? '').toLowerCase();
      if (session == 'wayland' && display.isEmpty) {
        return const UnsupportedHostControl(
          'linux-wayland (#151: Wayland needs xdg-desktop-portal)',
        );
      }
      if (display.isEmpty) {
        return const UnsupportedHostControl(
          'linux (no X11 display: DISPLAY is not set)',
        );
      }
      return LinuxX11HostControl();
    }
    return UnsupportedHostControl(os);
  }
}

/// macOS host: the existing MethodChannel bridge (ScreenCaptureKit +
/// CGEvent/Accessibility).
class MacHostControl extends ChannelControl implements HostControl {
  const MacHostControl();

  @override
  Future<bool> isTrusted() => NativeControl.isTrusted();
  @override
  Future<void> askPermission() => NativeControl.askPermission();
  @override
  Future<void> openAccessibilitySettings() =>
      NativeControl.openAccessibilitySettings();
}

/// Placeholder for platforms with no host bridge yet. Fails loudly with a
/// plain reason instead of a missing-plugin crash.
class UnsupportedHostControl implements HostControl {
  const UnsupportedHostControl(this.operatingSystem);

  final String operatingSystem;

  Never _unsupported() => throw UnsupportedError(
    'Host control is not available on $operatingSystem yet. '
    'Screen capture, input and accessibility need a native bridge first.',
  );

  @override
  Future<bool> isTrusted() => _unsupported();
  @override
  Future<void> askPermission() => _unsupported();
  @override
  Future<void> openAccessibilitySettings() => _unsupported();
  @override
  Future<ScreenSnapshot> snapshot() => _unsupported();
  @override
  Future<ScreenSnapshot> snapshotRegion(
    double x,
    double y,
    double width,
    double height,
  ) => _unsupported();
  @override
  Future<Offset> mouseLocation() => _unsupported();
  @override
  Future<ResolvedTarget> resolveTarget(String id) => _unsupported();
  @override
  Future<void> warp(double x, double y) => _unsupported();
  @override
  Future<void> click(double x, double y, {bool right = false, int count = 1}) =>
      _unsupported();
  @override
  Future<void> drag(Offset from, Offset to) => _unsupported();
  @override
  Future<void> scroll(double x, double y, {int dx = 0, int dy = 0}) =>
      _unsupported();
  @override
  Future<void> type(String text) => _unsupported();
  @override
  Future<String?> press(String combo) => _unsupported();
  @override
  Future<String?> openApp(String name) => _unsupported();
  @override
  Future<String?> openURL(String url) => _unsupported();
}
