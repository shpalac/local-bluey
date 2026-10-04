import 'dart:async';

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

  static const CheckResult _pairingUnknown = CheckResult(
    id: 'pairing',
    titleEn: 'Phone pairing',
    titleHe: 'צימוד טלפון',
    status: CheckStatus.unknown,
  );

  /// Runs every check; tests inject fakes via [overrides] (#85).
  static Future<List<CheckResult>> run({Map<String, Check>? overrides}) async {
    final checks = <String, Check>{
      'provider': _providerReachable,
      'pairing': () async => _pairingUnknown,
    };
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
