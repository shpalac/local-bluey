import 'package:shared_preferences/shared_preferences.dart';

import 'settings_store.dart';

/// Local-only enforcement + screenshot text redaction (#26).
class PrivacyGuard {
  PrivacyGuard._();

  static const _kLocalOnly = 'privacy.localOnly';

  static Future<bool> isLocalOnly() async =>
      (await SharedPreferences.getInstance()).getBool(_kLocalOnly) ?? false;

  static Future<void> setLocalOnly(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_kLocalOnly, value);

  /// True when this settings' endpoint is on this machine.
  static bool isLocalUrl(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host.endsWith('.local');
  }

  /// In local-only mode, remote endpoints are refused with a plain reason.
  static Future<String?> refusal(BrainSettings settings) async {
    if (!await isLocalOnly()) return null;
    if (!isLocalUrl(settings.baseUrl)) {
      return 'Local-only mode is on - ${settings.baseUrl} is off-device.';
    }
    return null;
  }

  /// Patterns scrubbed from screen text before it reaches the brain.
  static final _patterns = [
    RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.]+\b'), // emails
    RegExp(r'\b\d{4}[ -]?\d{4}[ -]?\d{4}[ -]?\d{4}\b'), // card numbers
    RegExp(r'\b\d{9}\b'), // national-id shaped numbers
  ];

  static String redact(String text) {
    var out = text;
    for (final pattern in _patterns) {
      out = out.replaceAllMapped(pattern, (m) => '[redacted]');
    }
    return out;
  }
}
