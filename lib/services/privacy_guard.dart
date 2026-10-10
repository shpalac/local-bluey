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
    return preferences.read();
  }

  /// Shared preference owner, independent of URL/redaction policy.
  static final _preferences = LocalOnlyPreferences();

  /// Isolated actual storage owner for fixtures.
  @visibleForTesting
  static LocalOnlyPreferences? debugPreferences;

  /// Active owner used by registry and Settings.
  static LocalOnlyPreferences get preferences =>
      debugPreferences ?? _preferences;

  /// Persists before reporting a successful local-only choice.
  static Future<void> setLocalOnly(bool value) => preferences.set(value);

  /// Explicit ordered registry deletion, default false after success.
  static Future<void> clearLocalOnly() => preferences.clear();

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
    return isLocalHost(uri.host);
  }

  /// Classifies bare retained host metadata without URL construction or DNS.
  /// Accepts only supported loopback forms; malformed/LAN/unknown hosts fail.
  static bool isLocalHost(String value) {
    var host = value.toLowerCase();
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (host == 'localhost' || host == '::1' || host == '0.0.0.0') return true;
    if (host.startsWith('::ffff:')) host = host.substring(7);
    final parts = host.split('.');
    if (parts.length != 4 || parts.first != '127') return false;
    return parts.every(
      (part) =>
          RegExp(r'^[0-9]{1,3}$').hasMatch(part) &&
          int.parse(part) >= 0 &&
          int.parse(part) <= 255,
    );
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

/// Safe storage uncertainty. Never implies that remote calls are allowed.
class PrivacyStorageException implements Exception {
  /// Creates a generic preference failure.
  const PrivacyStorageException();
  @override
  String toString() =>
      'Local-only preference could not be verified or updated.';
}

/// Orders actual preference reads, writes and explicit deletion.
class LocalOnlyPreferences extends ChangeNotifier {
  /// Uses preferences by default or injected actual operations for tests.
  LocalOnlyPreferences({
    Future<bool?> Function()? read,
    Future<bool> Function(bool)? write,
    Future<bool> Function()? remove,
  }) : _read =
           read ??
           (() async => (await SharedPreferences.getInstance()).getBool(
             PrivacyGuard._kLocalOnly,
           )),
       _write =
           write ??
           ((value) async => (await SharedPreferences.getInstance()).setBool(
             PrivacyGuard._kLocalOnly,
             value,
           )),
       _remove =
           remove ??
           (() async => (await SharedPreferences.getInstance()).remove(
             PrivacyGuard._kLocalOnly,
           ));

  final Future<bool?> Function() _read;
  final Future<bool> Function(bool) _write;
  final Future<bool> Function() _remove;
  Future<void>? _tail;
  int _revision = 0;
  int _clearEpoch = 0;
  bool? _value;

  /// Last verified preference, null if not yet verified or read failed.
  bool? get value => _value;

  void _publish(bool? value, int revision) {
    if (revision != _revision) return;
    _value = value;
    notifyListeners();
  }

  Future<T> _enqueue<T>(
    Future<T> Function(int) action, {
    bool mutation = true,
  }) {
    final revision = mutation ? ++_revision : _revision;
    final next = (_tail ?? Future<void>.value()).then((_) async {
      try {
        return await action(revision);
      } catch (_) {
        if (revision == _revision) {
          try {
            _publish(await _read() ?? false, revision);
          } catch (_) {
            _publish(null, revision);
          }
        }
        throw const PrivacyStorageException();
      }
    });
    final settled = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tail = settled;
    settled.then((_) {
      if (identical(_tail, settled)) _tail = null;
    });
    return next;
  }

  /// Fresh source read; superseded or failed reads never fabricate OFF.
  Future<bool> read() => _enqueue((revision) async {
    final value = await _read() ?? false;
    if (revision != _revision) throw const PrivacyStorageException();
    _publish(value, revision);
    return value;
  }, mutation: false);

  /// Persists and reconciles actual state before success publication.
  Future<void> set(bool value) {
    final epoch = _clearEpoch;
    return _enqueue((revision) async {
      if (epoch != _clearEpoch) return;
      if (!await _write(value)) throw const PrivacyStorageException();
      _publish(await _read() ?? false, revision);
    });
  }

  /// Orders removal behind entered writes; invalidates older queued choices.
  Future<void> clear() {
    _clearEpoch++;
    return _enqueue((revision) async {
      if (!await _remove()) throw const PrivacyStorageException();
      _publish(await _read() ?? false, revision);
    });
  }
}
