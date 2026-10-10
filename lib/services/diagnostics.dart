import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:http/http.dart' as http;

import 'privacy_guard.dart';
import 'settings_store.dart';

/// One troubleshooting check outcome (#85): never a false pass - anything
/// we cannot verify reports unknown, not pass.
enum CheckStatus { pass, fail, unknown }

/// Outcome of one troubleshooting check (#85).
class CheckResult {
  const CheckResult({
    required this.id,
    required this.titleEn,
    required this.titleHe,
    required this.status,
    this.fixEn,
    this.fixHe,
  });

  /// Stable check identifier.
  final String id;

  /// Check title, English.
  final String titleEn;

  /// Check title, Hebrew.
  final String titleHe;

  /// What the check found.
  final CheckStatus status;

  /// The exact fix when failing (open system settings, edit URL, re-pair).
  final String? fixEn;

  /// Same, Hebrew.
  final String? fixHe;
}

/// One troubleshooting check.
typedef Check = Future<CheckResult> Function();

/// Live troubleshooting checks + redacted diagnostics report (#85).
class Diagnostics {
  Diagnostics._();

  /// Tests exercise the actual bounded provider probe without real endpoints.
  /// Successful headers mean reachability only, never model/auth readiness.
  /// Owns and closes only its default client. Shared clients remain open;
  /// timeout discards late headers, not guaranteed transport abort.
  static Future<CheckResult> providerReachable({
    Future<BrainSettings> Function()? settings,
    Future<bool> Function()? localOnly,
    http.Client? client,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    var active = true;
    final transport = client ?? http.Client();
    Future<CheckResult> probe() async {
      final config = await (settings ?? SettingsStore.load)();
      final local = await (localOnly ?? PrivacyGuard.isLocalOnly)();
      if (!active) return _providerResult(CheckStatus.fail);
      final uri = Uri.tryParse(config.baseUrl.trim());
      if (uri == null ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.userInfo.isNotEmpty) {
        return _providerResult(
          CheckStatus.fail,
          'The provider URL is invalid or unsupported - edit it in Settings.',
          'כתובת הספק לא תקינה או לא נתמכת - עדכן בהגדרות.',
        );
      }
      if (local && !PrivacyGuard.isLocalUrl(config.baseUrl)) {
        return _providerResult(
          CheckStatus.fail,
          'Local-only mode is on but the provider URL is remote - point it at a local server or turn local-only off in Settings.',
          'מצב מקומי-בלבד פעיל אבל הכתובת חיצונית - עדכן בהגדרות.',
        );
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await transport.send(request);
      // Header-only probe: no response data is needed, including stalled body.
      // Cancel our listener even for late headers. Cancellation may settle
      // later/fail; it must not extend the probe or close a shared client.
      unawaited(
        response.stream
            .listen((_) {}, onError: (Object _) {})
            .cancel()
            .catchError((Object _) {}),
      );
      if (!active) return _providerResult(CheckStatus.fail);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _providerResult(
          CheckStatus.fail,
          'The provider did not return a successful HTTP response - check its URL and server in Settings. Redirects are not followed.',
          'הספק לא החזיר תשובת HTTP מוצלחת - בדוק את הכתובת והשרת בהגדרות. הפניות לא נעקבות.',
        );
      }
      return _providerResult(
        CheckStatus.pass,
        'HTTP endpoint reachable only; model, capability and authentication are not verified.',
        'נקודת HTTP נגישה בלבד; מודל, יכולות ואימות לא נבדקו.',
      );
    }

    try {
      return await probe().timeout(
        timeout,
        onTimeout: () {
          active = false;
          return _providerResult(
            CheckStatus.fail,
            'The provider did not answer in time - check the URL and that the server is running (Settings).',
            'הספק לא ענה בזמן - בדוק את הכתובת ושהשרת פעיל.',
          );
        },
      );
    } catch (_) {
      return _providerResult(CheckStatus.unknown);
    } finally {
      active = false;
      if (client == null) transport.close();
    }
  }

  static CheckResult _providerResult(
    CheckStatus status, [
    String? en,
    String? he,
  ]) => CheckResult(
    id: 'provider',
    titleEn: 'Brain HTTP reachability (not model readiness)',
    titleHe: 'נגישות HTTP של המוח (לא מוכנות מודל)',
    status: status,
    fixEn: en,
    fixHe: he,
  );

  /// Linux runtime dependency check (#152): looks up a binary on PATH and
  /// reports unknown on non-Linux or lookup failure - never a false pass.
  static Check _linuxBinary(
    String id,
    String binary,
    String titleEn,
    String titleHe,
    String fixEn,
    String fixHe, {
    required bool Function() isLinux,
    required Future<bool> Function(String) which,
  }) {
    return () async {
      if (!isLinux()) {
        return CheckResult(
          id: id,
          titleEn: titleEn,
          titleHe: titleHe,
          status: CheckStatus.unknown,
        );
      }
      try {
        final found = await which(binary);
        return CheckResult(
          id: id,
          titleEn: titleEn,
          titleHe: titleHe,
          status: found ? CheckStatus.pass : CheckStatus.fail,
          fixEn: found ? null : fixEn,
          fixHe: found ? null : fixHe,
        );
      } catch (_) {
        return CheckResult(
          id: id,
          titleEn: titleEn,
          titleHe: titleHe,
          status: CheckStatus.unknown,
        );
      }
    };
  }

  static Future<bool> _which(String binary) async {
    final result = await Process.run('which', [binary]);
    return result.exitCode == 0;
  }

  /// Linux dependency checks (#152). Injectable seams keep tests off the
  /// real platform: [isLinux] and [which].
  static Map<String, Check> linuxChecks({
    bool Function()? isLinux,
    Future<bool> Function(String)? which,
  }) {
    final platform = isLinux ?? () => Platform.isLinux;
    final lookup = which ?? _which;
    return {
      'linux_display': _linuxBinary(
        'linux_display',
        'xdg-desktop-portal',
        'Desktop portal (screen access)',
        'פורטל שולחן העבודה (גישה למסך)',
        'Install the desktop portal: sudo apt install xdg-desktop-portal xdg-desktop-portal-gtk (Wayland) or run an X11 session',
        'התקן את הפורטל: sudo apt install xdg-desktop-portal xdg-desktop-portal-gtk (Wayland) או עבור לסשן X11',
        isLinux: platform,
        which: lookup,
      ),
      'linux_keyring': _linuxBinary(
        'linux_keyring',
        'secret-tool',
        'Keyring (secret-tool)',
        'צרור מפתחות (secret-tool)',
        'Install libsecret tools: sudo apt install libsecret-1-0 libsecret-tools',
        'התקן את כלי libsecret: sudo apt install libsecret-1-0 libsecret-tools',
        isLinux: platform,
        which: lookup,
      ),
      'linux_discovery': _linuxBinary(
        'linux_discovery',
        'avahi-browse',
        'Network discovery (Avahi)',
        'גילוי רשת (Avahi)',
        'Install Avahi: sudo apt install avahi-daemon avahi-utils',
        'התקן את Avahi: sudo apt install avahi-daemon avahi-utils',
        isLinux: platform,
        which: lookup,
      ),
      'linux_audio': _linuxBinary(
        'linux_audio',
        'gst-launch-1.0',
        'Audio pipeline (GStreamer)',
        'צינור שמע (GStreamer)',
        'Install GStreamer tools: sudo apt install gstreamer1.0-tools gstreamer1.0-plugins-good',
        'התקן את כלי GStreamer: sudo apt install gstreamer1.0-tools gstreamer1.0-plugins-good',
        isLinux: platform,
        which: lookup,
      ),
    };
  }

  static const CheckResult _pairingUnknown = CheckResult(
    id: 'pairing',
    titleEn: 'Phone pairing',
    titleHe: 'צימוד טלפון',
    status: CheckStatus.unknown,
  );

  static CheckResult _unknownFor(String id) {
    final (en, he) = switch (id) {
      'provider' => (
        'Brain HTTP reachability (not model readiness)',
        'נגישות HTTP של המוח (לא מוכנות מודל)',
      ),
      'pairing' => ('Phone pairing', 'צימוד טלפון'),
      'linux_display' => (
        'Desktop portal (screen access)',
        'פורטל שולחן העבודה (גישה למסך)',
      ),
      'linux_keyring' => ('Keyring (secret-tool)', 'צרור מפתחות (secret-tool)'),
      'linux_discovery' => ('Network discovery (Avahi)', 'גילוי רשת (Avahi)'),
      'linux_audio' => ('Audio pipeline (GStreamer)', 'צינור שמע (GStreamer)'),
      _ => ('Additional diagnostic check', 'בדיקת אבחון נוספת'),
    };
    return CheckResult(
      id: id,
      titleEn: en,
      titleHe: he,
      status: CheckStatus.unknown,
    );
  }

  /// Runs sequential checks with one result per key, in insertion order (#85).
  /// Each check has a five-second default deadline (including the provider's
  /// four-second transport budget). Throws/timeouts/mismatched ids become
  /// unknown for the actual key with trusted built-in or generic metadata.
  /// Late success/errors are discarded, not underlying process/network abort.
  /// Tests inject offline checks via [overrides]. Timeout must be positive.
  static Future<List<CheckResult>> run({
    Map<String, Check>? overrides,
    Duration checkTimeout = const Duration(seconds: 5),
    bool Function()? isLinux,
    Future<bool> Function(String)? which,
  }) async {
    if (checkTimeout <= Duration.zero) {
      throw ArgumentError.value(
        checkTimeout,
        'checkTimeout',
        'Must be positive',
      );
    }
    final checks = <String, Check>{
      'provider': providerReachable,
      'pairing': () async => _pairingUnknown,
    };
    linuxChecks(
      isLinux: isLinux,
      which: which,
    ).forEach((id, check) => checks[id] = check);
    overrides?.forEach((id, check) => checks[id] = check);
    final results = <CheckResult>[];
    for (final entry in checks.entries) {
      final unknown = _unknownFor(entry.key);
      try {
        final result = await entry
            .value()
            .then<CheckResult>(
              (result) => result,
              onError: (Object _) => unknown,
            )
            .timeout(checkTimeout, onTimeout: () => unknown);
        results.add(result.id == entry.key ? result : unknown);
      } catch (_) {
        results.add(unknown);
      }
    }
    return results;
  }

  static final _keyPattern = RegExp(r'(sk-[A-Za-z0-9_-]{8,}|Bearer \S+)');

  /// "Copy diagnostics" text: versions, platform, role, check results -
  /// no screenshots, audio, keys, or typed content (#85, #26, #57).
  static String buildReport({
    required String platform,
    required String role,
    required List<CheckResult> results,
    String? secretToRedact,
  }) {
    final buffer = StringBuffer()
      ..writeln('Local Bluey diagnostics')
      ..writeln('Platform: $platform')
      ..writeln('Role: $role');
    for (final r in results) {
      buffer.writeln('${r.id}: ${r.status.name}');
    }
    var report = buffer.toString();
    report = report.replaceAll(_keyPattern, '[redacted]');
    if (secretToRedact != null && secretToRedact.isNotEmpty) {
      report = report.replaceAll(secretToRedact, '[redacted]');
    }
    return report;
  }
}
