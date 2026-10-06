import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_store.dart';

/// Local-only enforcement + screenshot text redaction (#26).
class PrivacyGuard {
  PrivacyGuard._();

  static const _kLocalOnly = 'privacy.localOnly';

  /// Test seam: bypasses SharedPreferences entirely (#120 tests).
  @visibleForTesting
  static bool? debugLocalOnlyOverride;

  /// Whether the user enabled local-only mode (no cloud calls, #120).
  static Future<bool> isLocalOnly() async {
    final override = debugLocalOnlyOverride;
    if (override != null) return override;
    return (await SharedPreferences.getInstance()).getBool(_kLocalOnly) ??
        false;
  }

  /// Persists the local-only setting.
  static Future<void> setLocalOnly(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_kLocalOnly, value);

  /// True when [url] points at this machine (#121).
  ///
  /// Loopback only: localhost, all of 127.0.0.0/8, 0.0.0.0, ::1 and
  /// IPv4-mapped loopback. A `.local` mDNS name is ANOTHER device on the
  /// network (or a spoofed answer), so it no longer counts as local -
  /// local-only means data does not leave this machine.
  static bool isLocalUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    var host = uri.host.toLowerCase();
    // Strip IPv6 brackets form variants.
    if (host == 'localhost' || host == '::1') return true;
    if (host == '0.0.0.0') return true;
    if (host.startsWith('::ffff:')) host = host.substring(7);
    final parts = host.split('.');
    if (parts.length == 4 && parts.every((p) => int.tryParse(p) != null)) {
      return parts[0] == '127';
    }
    return false;
  }

  /// In local-only mode, remote endpoints are refused with a plain reason.
  static Future<String?> refusal(BrainSettings settings) =>
      refusalForUrl(settings.baseUrl);

  /// Same refusal check for any resolved endpoint URL, so transcription and
  /// TTS services are gated exactly like the brain (#120).
  static Future<String?> refusalForUrl(String url) async {
    if (!await isLocalOnly()) return null;
    if (!isLocalUrl(url)) {
      return 'Local-only mode is on - $url is off-device.';
    }
    return null;
  }

  /// True when [text] contains anything the redaction patterns would scrub
  /// (#122): if the text needed scrubbing, the screenshot of the same screen
  /// shows the same sensitive data and must not be sent either.
  static bool hasSensitive(String text) =>
      _patterns.any((pattern) => pattern.hasMatch(text));

  /// Patterns scrubbed from screen text before it reaches the brain.
  static final _patterns = [
    RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.]+\b'), // emails
    RegExp(r'\b\d{4}[ -]?\d{4}[ -]?\d{4}[ -]?\d{4}\b'), // card numbers
    RegExp(r'\b\d{9}\b'), // national-id shaped numbers
  ];

  /// Scrubs emails, card-shaped and national-id-shaped numbers from
  /// [text] before it leaves the device (#86).
  static String redact(String text) {
    var out = text;
    for (final pattern in _patterns) {
      out = out.replaceAllMapped(pattern, (m) => '[redacted]');
    }
    return out;
  }
}
