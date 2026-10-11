import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/host_control.dart';
import 'package:local_bluey/services/linux_portal_host_control.dart';
import 'package:local_bluey/services/linux_x11_host_control.dart';
import 'package:local_bluey/services/support_matrix.dart';

void main() {
  final expected = {
    'macos': (
      AppRole.host,
      {
        SupportMatrix.hostControl,
        SupportMatrix.windowManagement,
        SupportMatrix.holdToTalk,
        SupportMatrix.phoneServer,
        SupportMatrix.macLink,
      },
    ),
    'ios': (
      AppRole.phoneClient,
      {SupportMatrix.holdToTalk, SupportMatrix.macLink},
    ),
    'android': (
      AppRole.phoneClient,
      {SupportMatrix.holdToTalk, SupportMatrix.macLink},
    ),
    'linux': (AppRole.unsupported, {SupportMatrix.holdToTalk}),
    'windows': (AppRole.unsupported, {SupportMatrix.holdToTalk}),
    'unknown-fixture': (AppRole.unsupported, <String>{}),
  };
  for (final entry in expected.entries) {
    test('${entry.key} exact role/capabilities, no unknown action', () {
      final p = SupportMatrix.profile(operatingSystem: entry.key);
      expect(p.os, entry.key);
      expect(p.role, entry.value.$1);
      expect(p.capabilities, entry.value.$2);
      expect(p.supports('invented-capability'), isFalse);
      expect(
        () => p.capabilities.add('injected-capability'),
        throwsUnsupportedError,
      );
      expect(
        SupportMatrix.profile(operatingSystem: entry.key)
            .supports('injected-capability'),
        isFalse,
      );
      if (entry.value.$1 != AppRole.host) {
        expect(p.supports(SupportMatrix.hostControl), isFalse);
        expect(p.supports(SupportMatrix.phoneServer), isFalse);
        expect(p.supports(SupportMatrix.windowManagement), isFalse);
      }
    });
  }
  for (final os in ['ios', 'android', 'windows', 'unknown-fixture']) {
    test('$os cannot invoke any HostControl operation', () {
      final host = HostControl.forPlatform(
        operatingSystem: os,
        environment: const {'DISPLAY': ':99', 'XDG_SESSION_TYPE': 'wayland'},
      );
      expect(host, isA<UnsupportedHostControl>());
      final calls = <Object? Function()>[
        host.isTrusted,
        host.askPermission,
        host.openAccessibilitySettings,
        host.snapshot,
        () => host.snapshotRegion(0, 0, 1, 1),
        host.mouseLocation,
        () => host.resolveTarget('synthetic'),
        () => host.warp(0, 0),
        () => host.click(0, 0),
        () => host.drag(Offset.zero, const Offset(1, 1)),
        () => host.scroll(0, 0),
        () => host.type('fabricated'),
        () => host.press('ENTER'),
        () => host.openApp('Synthetic'),
        () => host.openURL('https://fixture.invalid'),
      ];
      for (final call in calls) {
        expect(
          call,
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'reason',
              contains(os),
            ),
          ),
        );
      }
    });
  }
  test('Linux factory environment selection does not upgrade public role', () {
    final cases = <(Map<String, String>, String, Matcher)>[
      (const {}, 'unsupported', isA<UnsupportedHostControl>()),
      (const {'DISPLAY': ':99'}, 'x11', isA<LinuxX11HostControl>()),
      (
        const {'XDG_SESSION_TYPE': 'WAYLAND'},
        'portal',
        isA<LinuxPortalHostControl>(),
      ),
      (
        const {'XDG_SESSION_TYPE': 'wayland', 'DISPLAY': ':99'},
        'portal',
        isA<LinuxPortalHostControl>(),
      ),
    ];
    for (final (env, mode, type) in cases) {
      expect(HostControl.linuxHostMode(environment: env), mode);
      expect(
        HostControl.forPlatform(operatingSystem: 'linux', environment: env),
        type,
      );
      expect(
        SupportMatrix.resolveRole(operatingSystem: 'linux'),
        AppRole.unsupported,
      );
    }
    expect(
      HostControl.forPlatform(operatingSystem: 'macos', environment: const {}),
      isA<MacHostControl>(),
    );
  });
}
