import 'dart:io';

import 'strings.dart';

/// What the app is on this device: the host (the Mac being controlled) or a
/// phone client (remote mic + face). Resolved from capabilities, never from
/// scattered Platform checks (#51).
enum AppRole { host, phoneClient, unsupported }

class PlatformProfile {
  const PlatformProfile(
    this.os, {
    required this.role,
    required this.capabilities,
  });

  final String os;
  final AppRole role;
  final Set<String> capabilities;

  bool supports(String capability) => capabilities.contains(capability);
}

class SupportMatrix {
  static const hostControl = 'hostControl';
  static const windowManagement = 'windowManagement';
  static const holdToTalk = 'holdToTalk';
  static const phoneServer = 'phoneServer';
  static const macLink = 'macLink';

  static const _profiles = {
    'macos': PlatformProfile(
      'macos',
      role: AppRole.host,
      capabilities: {
        hostControl,
        windowManagement,
        holdToTalk,
        phoneServer,
        macLink,
      },
    ),
    'ios': PlatformProfile(
      'ios',
      role: AppRole.phoneClient,
      capabilities: {holdToTalk, macLink},
    ),
    'android': PlatformProfile(
      'android',
      role: AppRole.phoneClient,
      capabilities: {holdToTalk, macLink},
    ),
    'linux': PlatformProfile(
      'linux',
      role: AppRole.unsupported,
      capabilities: {holdToTalk},
    ),
    'windows': PlatformProfile(
      'windows',
      role: AppRole.unsupported,
      capabilities: {holdToTalk},
    ),
  };

  static PlatformProfile profile({String? operatingSystem}) {
    final os = operatingSystem ?? Platform.operatingSystem;
    return _profiles[os] ??
        PlatformProfile(os, role: AppRole.unsupported, capabilities: const {});
  }

  static AppRole resolveRole({String? operatingSystem}) =>
      profile(operatingSystem: operatingSystem).role;

  /// Why this platform has no supported role (#84). Localized for the
  /// unsupported screen.
  static String unsupportedReason(PlatformProfile profile) {
    if (!_profiles.containsKey(profile.os)) {
      return Strings.t(
        'This operating system (${profile.os}) is not recognized.',
        'מערכת ההפעלה (${profile.os}) לא מוכרת.',
      );
    }
    return Strings.t(
      'This platform can be neither a host nor a remote client.',
      'הפלטפורמה הזו לא יכולה לשמש כמארח וגם לא כשלט.',
    );
  }

  /// Name this device presents to its pair over the link.
  static String deviceName({String? operatingSystem}) =>
      switch (operatingSystem ?? Platform.operatingSystem) {
        'ios' => 'iPhone',
        'android' => 'Android phone',
        'macos' => 'Mac',
        _ => 'Device',
      };
}
