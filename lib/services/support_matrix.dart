import 'dart:io';

import 'strings.dart';

/// What the app is on this device: the host (the Mac being controlled) or a
/// phone client (remote mic + face). Resolved from capabilities, never from
/// scattered Platform checks (#51).
enum AppRole { host, phoneClient, unsupported }

/// One OS's role and capability set (#51).
class PlatformProfile {
  const PlatformProfile(
    this.os, {
    required this.role,
    required this.capabilities,
  });

  /// [Platform.operatingSystem] value this profile describes.
  final String os;

  /// What the app is on this OS.
  final AppRole role;

  /// Capability ids (the SupportMatrix constants) this OS has.
  final Set<String> capabilities;

  /// Whether this profile has [capability].
  bool supports(String capability) => capabilities.contains(capability);
}

/// The single capability map for the whole app (#51): screens and
/// services ask here instead of sprinkling Platform checks.
class SupportMatrix {
  /// Screen capture, input and accessibility control.
  static const hostControl = 'hostControl';

  /// Window positioning/minimize via window_manager.
  static const windowManagement = 'windowManagement';

  /// Push-to-talk mic capture.
  static const holdToTalk = 'holdToTalk';

  /// Acting as the server a phone pairs to.
  static const phoneServer = 'phoneServer';

  /// Acting as the client of a paired Mac.
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

  /// The profile for [operatingSystem] (defaults to this device);
  /// unknown OSes get an unsupported profile with no capabilities.
  static PlatformProfile profile({String? operatingSystem}) {
    final os = operatingSystem ?? Platform.operatingSystem;
    return _profiles[os] ??
        PlatformProfile(os, role: AppRole.unsupported, capabilities: const {});
  }

  /// Convenience: just the role for [operatingSystem].
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
