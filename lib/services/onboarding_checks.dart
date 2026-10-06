import 'native_control.dart';
import 'strings.dart';

/// Injectable permission checks for onboarding (#86): live status per
/// permission, fakes in tests.
abstract class PermissionChecker {
  /// macOS accessibility permission (input control).
  Future<bool> accessibility();

  /// macOS screen-recording permission; never prompts (#174).
  Future<bool> screenRecording();

  /// Microphone permission; never prompts (#174).
  Future<bool> microphone();

  /// Local-network permission (phone pairing over Bonjour).
  Future<bool> localNetwork();
}

/// Production checker: reads the live OS permission state.
class LivePermissionChecker implements PermissionChecker {
  const LivePermissionChecker();

  @override
  Future<bool> accessibility() => NativeControl.isTrusted();

  // No cheap in-app probe: these are requested lazily when their feature is
  // first used (#86), so onboarding treats them as "not needed yet".
  // Real preflights (#174): these never prompt - the requests themselves
  // stay lazy (#86), fired by the feature that needs them.
  @override
  Future<bool> screenRecording() => NativeControl.screenCaptureAccess();
  @override
  Future<bool> microphone() => NativeControl.microphoneAccess();

  // No preflight API exists for Local Network on macOS: it is requested
  // lazily by Bonjour and stays "not needed yet" here.
  @override
  Future<bool> localNetwork() async => false;
}

/// One permission the onboarding/recovery flow explains and links to.
class OnboardingPermission {
  const OnboardingPermission({
    required this.id,
    required this.title,
    required this.why,
    required this.settingsUrl,
    required this.requiredForFirstAnswer,
    required this.titleHe,
    required this.whyHe,
  });

  /// Stable identifier used by the watchdog's baseline.
  final String id;

  /// Short display name.
  final String title;

  /// Hebrew [title] for the Hebrew UI (#227).
  final String titleHe;

  /// Hebrew [why] for the Hebrew UI (#227).
  final String whyHe;

  /// [title] in the active UI language.
  String get localTitle => Strings.t(title, titleHe);

  /// [why] in the active UI language.
  String get localWhy => Strings.t(why, whyHe);

  /// Plain-language reason the app needs it.
  final String why;

  /// Deep link into the matching System Settings pane.
  final String settingsUrl;

  /// Lazy requests keep the minimal path short (#86): only what the first
  /// feature needs is required to finish onboarding.
  final bool requiredForFirstAnswer;
}

/// Every permission the onboarding flow walks through, in order.
const onboardingPermissions = [
  OnboardingPermission(
    id: 'accessibility',
    title: 'Accessibility',
    why: 'Lets Bluey point and click for you.',
    titleHe: 'נגישות',
    whyHe: 'מאפשר לבלואי להצביע וללחוץ בשבילך.',
    settingsUrl: 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    requiredForFirstAnswer: false,
  ),
  OnboardingPermission(
    id: 'screen_recording',
    title: 'Screen Recording',
    why: 'Lets Bluey see what is on your screen.',
    titleHe: 'הקלטת מסך',
    whyHe: 'מאפשר לבלואי לראות מה על המסך שלך.',
    settingsUrl: 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
    requiredForFirstAnswer: false,
  ),
  OnboardingPermission(
    id: 'microphone',
    title: 'Microphone',
    why: 'Lets Bluey hear you while you hold to talk.',
    titleHe: 'מיקרופון',
    whyHe: 'מאפשר לבלואי לשמוע אותך בזמן שאתה לוחץ ומחזיק כדי לדבר.',
    settingsUrl: 'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
    requiredForFirstAnswer: true,
  ),
  OnboardingPermission(
    id: 'local_network',
    title: 'Local Network',
    why: 'Lets your iPhone find this Mac.',
    titleHe: 'רשת מקומית',
    whyHe: 'מאפשר ל-iPhone שלך למצוא את ה-Mac הזה.',
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
