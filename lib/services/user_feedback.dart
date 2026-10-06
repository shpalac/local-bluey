import 'strings.dart';

/// The known failure surfaces (#89). Every value maps to a pattern; the test
/// enumerates the enum and fails on an unmapped one.
enum FailureKind {
  /// The configured LLM/STT endpoint did not answer.
  providerUnreachable,

  /// A required OS permission (mic, accessibility, ...) is missing.
  permissionMissing,

  /// The paired Mac is unreachable.
  macOffline,

  /// No paired Mac was found at all.
  macNotFound,

  /// No brain/STT provider has been configured yet.
  noProviderConfigured,

  /// The action needs conversation history and there is none.
  noHistory,

  /// The safety gate refused the action.
  actionRefused,

  /// The screen target being acted on went stale mid-flow.
  staleTarget,
}

/// One of three reusable patterns: an empty state (reason + one primary
/// action), a recoverable error (what, why, retry/fix), or undo (handled by
/// undo.dart).
class FeedbackSpec {
  const FeedbackSpec({
    required this.isEmptyState,
    required this.titleEn,
    required this.titleHe,
    required this.whyEn,
    required this.whyHe,
    required this.actionLabelEn,
    required this.actionLabelHe,
  });

  /// Empty states are calm and informational; recoverable errors ask for a
  /// retry or a fix.
  final bool isEmptyState;

  /// Title, English.
  final String titleEn;

  /// Title, Hebrew.
  final String titleHe;

  /// Explanation, English.
  final String whyEn;

  /// Explanation, Hebrew.
  final String whyHe;

  /// Primary action label, English.
  final String actionLabelEn;

  /// Primary action label, Hebrew.
  final String actionLabelHe;

  /// Localized title for the active locale.
  String get title => Strings.t(titleEn, titleHe);

  /// Localized explanation for the active locale.
  String get why => Strings.t(whyEn, whyHe);

  /// Localized action label for the active locale.
  String get actionLabel => Strings.t(actionLabelEn, actionLabelHe);
}

/// Maps every known failure to its pattern with plain-language text (#89).
FeedbackSpec feedbackFor(FailureKind kind) => switch (kind) {
  FailureKind.providerUnreachable => const FeedbackSpec(
    isEmptyState: false,
    titleEn: 'The brain is unreachable',
    titleHe: 'אי אפשר להגיע למוח',
    whyEn: 'The provider did not answer. Check the base URL and that the server is running.',
    whyHe: 'הספק לא ענה. בדקו את כתובת ה-URL ושהשרת פועל.',
    actionLabelEn: 'Test connection',
    actionLabelHe: 'בדיקת חיבור',
  ),
  FailureKind.permissionMissing => const FeedbackSpec(
    isEmptyState: false,
    titleEn: 'A permission is missing',
    titleHe: 'חסרה הרשאה',
    whyEn: 'Bluey needs this permission for the action to work.',
    whyHe: 'בלוי צריך את ההרשאה הזו כדי שהפעולה תעבוד.',
    actionLabelEn: 'Open settings',
    actionLabelHe: 'פתיחת הגדרות',
  ),
  FailureKind.macOffline => const FeedbackSpec(
    isEmptyState: false,
    titleEn: 'The Mac went offline',
    titleHe: 'המק התנתק',
    whyEn: 'The connection to the Mac dropped.',
    whyHe: 'החיבור למק נותק.',
    actionLabelEn: 'Reconnect',
    actionLabelHe: 'התחברות מחדש',
  ),
  FailureKind.macNotFound => const FeedbackSpec(
    isEmptyState: true,
    titleEn: 'No Mac found',
    titleHe: 'לא נמצא מק',
    whyEn: 'No Mac running Bluey is visible on this network yet.',
    whyHe: 'עדיין לא נראה מק עם בלוי ברשת הזו.',
    actionLabelEn: 'Search again',
    actionLabelHe: 'חיפוש מחדש',
  ),
  FailureKind.noProviderConfigured => const FeedbackSpec(
    isEmptyState: true,
    titleEn: 'No brain configured',
    titleHe: 'לא הוגדר מוח',
    whyEn: 'Set up a provider to start talking to Bluey.',
    whyHe: 'הגדירו ספק כדי להתחיל לדבר עם בלוי.',
    actionLabelEn: 'Open settings',
    actionLabelHe: 'פתיחת הגדרות',
  ),
  FailureKind.noHistory => const FeedbackSpec(
    isEmptyState: true,
    titleEn: 'No history yet',
    titleHe: 'אין עדיין היסטוריה',
    whyEn: 'Conversations and actions will appear here.',
    whyHe: 'שיחות ופעולות יופיעו כאן.',
    actionLabelEn: 'Start talking',
    actionLabelHe: 'התחילו לדבר',
  ),
  FailureKind.actionRefused => const FeedbackSpec(
    isEmptyState: false,
    titleEn: 'Action refused',
    titleHe: 'הפעולה נדחתה',
    whyEn: 'The safety gate blocked this action.',
    whyHe: 'שער הבטיחות חסם את הפעולה.',
    actionLabelEn: 'Review safety settings',
    actionLabelHe: 'בדיקת הגדרות בטיחות',
  ),
  FailureKind.staleTarget => const FeedbackSpec(
    isEmptyState: false,
    titleEn: 'The screen changed',
    titleHe: 'המסך השתנה',
    whyEn: 'What Bluey saw is no longer current, so the action was skipped.',
    whyHe: 'מה שבלוי ראה כבר לא עדכני, לכן הפעולה דולגה.',
    actionLabelEn: 'Look again',
    actionLabelHe: 'מבט מחדש',
  ),
};

/// Classifies tool/result error text to a known failure (#89). Returns null
/// for text that is not a known failure.
FailureKind? classifyFailure(String text) {
  final t = text.toLowerCase();
  if (t.startsWith('screen knowledge is stale')) return FailureKind.staleTarget;
  // Connectivity before "refused": "connection refused" is not the gate.
  if (t.contains('unreachable') ||
      t.contains('connection refused') ||
      t.contains('timed out') ||
      t.contains('socketexception')) {
    return FailureKind.providerUnreachable;
  }
  if (t.contains('refused') || t.contains('not confirmed')) {
    return FailureKind.actionRefused;
  }
  if (t.contains('accessibility') || t.contains('permission')) {
    return FailureKind.permissionMissing;
  }
  if (t.contains('offline') || t.contains('disconnected')) {
    return FailureKind.macOffline;
  }
  return null;
}
