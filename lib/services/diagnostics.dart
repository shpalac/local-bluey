import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:http/http.dart' as http;

import 'privacy_guard.dart';
import 'settings_store.dart';

/// One troubleshooting check outcome (#85): never a false pass - anything
/// we cannot verify reports unknown, not pass.
enum CheckStatus { pass, fail, unknown }

class CheckResult {
  const CheckResult({
    required this.id,
    required this.titleEn,
    required this.titleHe,
    required this.status,
    this.fixEn,
    this.fixHe,
  });

  final String id;
  final String titleEn;
  final String titleHe;
  final CheckStatus status;

  /// The exact fix when failing (open system settings, edit URL, re-pair).
  final String? fixEn;
  final String? fixHe;
}

typedef Check = Future<CheckResult> Function();

/// Live troubleshooting checks + redacted diagnostics report (#85).
class Diagnostics {
  Diagnostics._();

  static Future<CheckResult> _providerReachable() async {
    final settings = await SettingsStore.load();
    final localOnly = await PrivacyGuard.isLocalOnly();
    final isLocal =
        settings.baseUrl.contains('localhost') ||
        settings.baseUrl.contains('127.0.0.1');
    if (localOnly && !isLocal) {
      return const CheckResult(
        id: 'provider',
        titleEn: 'Brain provider',
        titleHe: 'ספק המוח',
        status: CheckStatus.fail,
        fixEn:
            'Local-only mode is on but the provider URL is remote - point it '
            'at a local server or turn local-only off in Settings.',
        fixHe: 'מצב מקומי-בלבד פעיל אבל הכתובת חיצונית - עדכן בהגדרות.',
      );
    }
    try {
      final uri = Uri.parse(settings.baseUrl);
      await http.get(uri).timeout(const Duration(seconds: 4));
      return const CheckResult(
        id: 'provider',
        titleEn: 'Brain provider',
        titleHe: 'ספק המוח',
        status: CheckStatus.pass,
      );
    } on TimeoutException {
      return const CheckResult(
        id: 'provider',
        titleEn: 'Brain provider',
        titleHe: 'ספק המוח',
        status: CheckStatus.fail,
        fixEn:
            'The provider did not answer in time - check the URL and '
            'that the server is running (Settings).',
        fixHe: 'הספק לא ענה בזמן - בדוק את הכתובת ושהשרת פעיל.',
      );
    } catch (_) {
      return const CheckResult(
        id: 'provider',
        titleEn: 'Brain provider',
        titleHe: 'ספק המוח',
        status: CheckStatus.unknown,
      );
    }
  }

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

  /// Runs every check; tests inject fakes via [overrides] (#85).
  static Future<List<CheckResult>> run({
    Map<String, Check>? overrides,
    bool Function()? isLinux,
    Future<bool> Function(String)? which,
  }) async {
    final checks = <String, Check>{
      'provider': _providerReachable,
      'pairing': () async => _pairingUnknown,
    };
    linuxChecks(
      isLinux: isLinux,
      which: which,
    ).forEach((id, check) => checks[id] = check);
    overrides?.forEach((id, check) => checks[id] = check);
    final results = <CheckResult>[];
    for (final check in checks.values) {
      try {
        results.add(await check());
      } catch (_) {
        results.add(_pairingUnknown);
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
