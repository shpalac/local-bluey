import 'native_control.dart';

/// Injectable permission checks for onboarding (#86): live status per
/// permission, fakes in tests.
abstract class PermissionChecker {
  Future<bool> accessibility();
  Future<bool> screenRecording();
  Future<bool> microphone();
  Future<bool> localNetwork();
}

class LivePermissionChecker implements PermissionChecker {
  const LivePermissionChecker();

  @override
  Future<bool> accessibility() => NativeControl.isTrusted();

  // No cheap in-app probe: these are requested lazily when their feature is
  // first used (#86), so onboarding treats them as "not needed yet".
  @override
  Future<bool> screenRecording() async => false;
  @override
  Future<bool> microphone() async => false;
  @override
  Future<bool> localNetwork() async => false;
}

class OnboardingPermission {
  const OnboardingPermission({
    required this.id,
    required this.title,
    required this.why,
    required this.settingsUrl,
    required this.requiredForFirstAnswer,
  });

  final String id;
  final String title;
  final String why;
  final String settingsUrl;

  /// Lazy requests keep the minimal path short (#86): only what the first
  /// feature needs is required to finish onboarding.
  final bool requiredForFirstAnswer;
}

const onboardingPermissions = [
  OnboardingPermission(
    id: 'accessibility',
    title: 'Accessibility',
    why: 'Lets Bluey point and click for you.',
    settingsUrl: 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    requiredForFirstAnswer: false,
  ),
  OnboardingPermission(
    id: 'screen_recording',
    title: 'Screen Recording',
    why: 'Lets Bluey see what is on your screen.',
    settingsUrl: 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
    requiredForFirstAnswer: false,
  ),
  OnboardingPermission(
    id: 'microphone',
    title: 'Microphone',
    why: 'Lets Bluey hear you while you hold to talk.',
    settingsUrl: 'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
    requiredForFirstAnswer: true,
  ),
  OnboardingPermission(
    id: 'local_network',
    title: 'Local Network',
    why: 'Lets your iPhone find this Mac.',
    settingsUrl: 'x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork',
    requiredForFirstAnswer: false,
  ),
];

/// True when every permission the first spoken answer needs is granted (#86).
Future<bool> requiredGranted(PermissionChecker checker) async {
  for (final p in onboardingPermissions) {
    if (!p.requiredForFirstAnswer) continue;
    final granted = await switch (p.id) {
      'accessibility' => checker.accessibility(),
      'screen_recording' => checker.screenRecording(),
      'microphone' => checker.microphone(),
      _ => checker.localNetwork(),
    };
    if (!granted) return false;
  }
  return true;
}
