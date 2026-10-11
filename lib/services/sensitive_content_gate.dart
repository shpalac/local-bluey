import 'privacy_guard.dart';

/// An intentionally small set of reason codes. Never log source text.
enum SensitiveVerdict {
  allow,
  unknown,
  locked,
  privateWindow,
  sensitiveWindow,
  sensitiveText,
  unverifiedText,
}

/// BLU-003: conservative classification before watch frame work or egress.
///
/// This is *not* a complete PII detector. Unknown metadata or failed OCR
/// refuses observation. It must be combined with per-session consent,
/// allowlisting, OS permissions, and the existing SafetyGate.
abstract final class SensitiveContentGate {
  static const int maxMetadataLength = 512;
  static const int maxEvidenceLength = 65536;

  static final _private = RegExp(
    r'\b(?:incognito|inprivate|private browsing|private window)\b|'
    r'גלישה פרטית|חלון פרטי',
    caseSensitive: false,
  );
  static final _windowSecrets = RegExp(
    r'\b(?:password|passcode|passwords|password manager|'
    r'sign[ -]?in|log[ -]?in|authentication|authenticator|'
    r'credentials|wallet|banking|bank account|payment details|'
    r'credit card|one[ -]?time password|two[ -]?factor|2fa)\b|'
    r'סיסמ(?:ה|אות)|כניסה לחשבון|התחברות|אימות|'
    r'תעודת זהות|כרטיס אשראי|פרטי אשראי|חשבון בנק|בנק',
    caseSensitive: false,
  );
  static final _contentSecrets = RegExp(
    r'\b(?:password|passcode|credentials|'
    r'api[ _-]?key|client[ _-]?secret|access[ _-]?token|'
    r'bearer|private[ _-]?key|secret[ _-]?key|'
    r'credit[ _-]?card|card[ _-]?number|cvv|iban|'
    r'social[ _-]?security|ssn|one[ -]?time password|otp)\b|'
    r'סיסמ(?:ה|אות)|תעודת זהות|מספר זהות|'
    r'מספר כרטיס|כרטיס אשראי|פרטי אשראי|'
    r'חשבון בנק|קוד אימות|קוד חד פעמי',
    caseSensitive: false,
  );
  static final _secretTokens = RegExp(
    r'\bAKIA[0-9A-Z]{16}\b|'
    r'\bgh[pousr]_[A-Za-z0-9_]{16,}\b|'
    r'\bsk-[A-Za-z0-9_-]{16,}\b',
  );

  /// Checks window/app metadata BEFORE any screenshot operation.
  static SensitiveVerdict beforeCapture({
    required String app,
    required String? title,
    bool locked = false,
  }) {
    if (locked) return SensitiveVerdict.locked;
    final normalizedApp = app.trim();
    final normalizedTitle = title?.trim() ?? '';
    if (normalizedApp.isEmpty ||
        normalizedTitle.isEmpty ||
        normalizedApp.length > maxMetadataLength ||
        normalizedTitle.length > maxMetadataLength) {
      return SensitiveVerdict.unknown;
    }
    final text = '$normalizedApp\n$normalizedTitle';
    if (_private.hasMatch(text)) return SensitiveVerdict.privateWindow;
    if (_windowSecrets.hasMatch(text) || PrivacyGuard.hasSensitive(text)) {
      return SensitiveVerdict.sensitiveWindow;
    }
    return SensitiveVerdict.allow;
  }

  /// OCR evidence MUST describe the exact pixels to be sent to the model.
  ///
  /// The caller is responsible for native OCR verification and focus
  /// consistency. A successful empty OCR result is distinct from no OCR.
  static SensitiveVerdict beforeEgress({
    required String? text,
    required bool exactFrameVerified,
  }) {
    if (!exactFrameVerified ||
        text == null ||
        text.length > maxEvidenceLength) {
      return SensitiveVerdict.unverifiedText;
    }
    if (_contentSecrets.hasMatch(text) ||
        _secretTokens.hasMatch(text) ||
        PrivacyGuard.hasSensitive(text)) {
      return SensitiveVerdict.sensitiveText;
    }
    return SensitiveVerdict.allow;
  }
}
