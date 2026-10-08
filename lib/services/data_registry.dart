import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'hold_key_controller.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'action_log.dart';
import 'characters.dart';
import 'conversation.dart';
import 'egress_monitor.dart';
import 'perf_monitor.dart';
import 'routines.dart';
import 'settings_store.dart';
import 'stt.dart';
import 'strings.dart';

/// One persistent store, registered in the single inventory (#83).
class DataStoreInfo {
  const DataStoreInfo({
    required this.id,
    required this.sourceFile,
    required this.whatEn,
    required this.whatHe,
    required this.where,
    required this.retentionEn,
    required this.retentionHe,
    required this.clear,
  });

  /// Stable id, e.g. 'action_log'.
  final String id;

  /// The lib/services (or lib/ui) file that owns this persistence, so the
  /// coverage test can fail when a new store is added without registering.
  final String sourceFile;

  /// What data is stored, English.
  final String whatEn;

  /// What data is stored, Hebrew.
  final String whatHe;

  /// Where it lives (SharedPreferences key, file path, ...).
  final String where;

  /// Retention policy, English.
  final String retentionEn;

  /// Retention policy, Hebrew.
  final String retentionHe;

  /// Deletes everything this store holds.
  final Future<void> Function() clear;
}

/// The one place that knows everything the app stores locally (#83).
class DataRegistry {
  DataRegistry._();

  static const _logRetention = 'Up to 500 entries / 30 days';

  /// Every local store in the app. The registry-coverage test fails when
  /// a new store appears in lib/services without an entry here.
  static final List<DataStoreInfo> stores = [
    DataStoreInfo(
      id: 'hold_key_pref',
      sourceFile: 'lib/services/hold_key_controller.dart',
      whatEn: 'Hold-to-talk key on/off, key and hold length',
      whatHe: 'העדפות מקש הדיבור: מופעל, מקש ומשך החזקה',
      where: 'SharedPreferences (holdkey.*)',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async {
        final prefs = await SharedPreferences.getInstance();
        for (final key in [
          'holdkey.enabled',
          'holdkey.key',
          'holdkey.thresholdMs',
        ]) {
          await prefs.remove(key);
        }
        await HoldKeySettings.instance.load();
      },
    ),
    DataStoreInfo(
      id: 'haptics_pref',
      sourceFile: 'lib/services/haptics.dart',
      whatEn: 'Haptics on/off preference',
      whatHe: 'העדפת רטט',
      where: 'SharedPreferences (haptics.enabled)',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async =>
          (await SharedPreferences.getInstance()).remove('haptics.enabled'),
    ),
    DataStoreInfo(
      id: 'app_lock_pref',
      sourceFile: 'lib/services/biometric_lock.dart',
      whatEn: 'App-lock on/off preference',
      whatHe: 'העדפת נעילת האפליקציה',
      where: 'SharedPreferences (lock.enabled)',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async =>
          (await SharedPreferences.getInstance()).remove('lock.enabled'),
    ),
    DataStoreInfo(
      id: 'notify_prefs',
      sourceFile: 'lib/services/discover.dart',
      whatEn: 'Per-type notification opt-ins',
      whatHe: 'הסכמות התראות לפי סוג',
      where: 'SharedPreferences (notify.*)',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async {
        final prefs = await SharedPreferences.getInstance();
        for (final key in prefs.getKeys().where(
          (k) => k.startsWith('notify.'),
        )) {
          await prefs.remove(key);
        }
      },
    ),
    DataStoreInfo(
      id: 'theme_mode_pref',
      sourceFile: 'lib/ui/theme.dart',
      whatEn: 'Appearance override (system/light/dark)',
      whatHe: 'העדפת מראה (מערכת/בהיר/כהה)',
      where: 'SharedPreferences (theme.mode)',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async =>
          (await SharedPreferences.getInstance()).remove('theme.mode'),
    ),
    DataStoreInfo(
      id: 'conversation',
      sourceFile: 'lib/services/conversation.dart',
      whatEn: 'Conversation history and running summary',
      whatHe: 'היסטוריית שיחות וסיכום שוטף',
      where: 'Documents/conversation.json',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () => ConversationStore.instance.clear(),
    ),
    DataStoreInfo(
      id: 'action_log',
      sourceFile: 'lib/services/action_log.dart',
      whatEn: 'Action log (what Bluey did, per run)',
      whatHe: 'יומן פעולות (מה בלוי עשה, לפי ריצה)',
      where: 'Documents/actions.jsonl',
      retentionEn: _logRetention,
      retentionHe: 'עד 500 רשומות / 30 יום',
      clear: () => ActionLog.instance.clear(),
    ),
    DataStoreInfo(
      id: 'egress',
      sourceFile: 'lib/services/egress_monitor.dart',
      whatEn: 'Egress record (what left the Mac, where to)',
      whatHe: 'רשומת תעבורה יוצאת (מה יצא מהמק, לאן)',
      where: 'Documents/egress.jsonl',
      retentionEn: _logRetention,
      retentionHe: 'עד 300 רשומות / 30 יום',
      clear: () => EgressMonitor.instance.clear(),
    ),
    DataStoreInfo(
      id: 'routines',
      sourceFile: 'lib/services/routines.dart',
      whatEn: 'Routines (saved command shortcuts)',
      whatHe: 'רוטינות (קיצורי פקודות שמורים)',
      where: 'Documents/routines.json',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () => RoutineStore.instance.clear(),
    ),
    DataStoreInfo(
      id: 'perf',
      sourceFile: 'lib/services/perf_monitor.dart',
      whatEn: 'Performance samples and overlay preference',
      whatHe: 'דגימות ביצועים והעדפת שכבת מדידה',
      where: 'Documents/perf.jsonl + SharedPreferences',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () => PerfMonitor.instance.clear(),
    ),
    DataStoreInfo(
      id: 'character',
      sourceFile: 'lib/services/characters.dart',
      whatEn: 'Selected character',
      whatHe: 'הדמות הנבחרת',
      where: 'SharedPreferences',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () => CharacterStore.instance.clear(),
    ),
    DataStoreInfo(
      id: 'settings',
      sourceFile: 'lib/services/settings_store.dart',
      whatEn: 'Brain/provider settings and the API key (Keychain)',
      whatHe: 'הגדרות ספק/מוח ומפתח API (בצרור המפתחות)',
      where: 'SharedPreferences + secure storage',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: SettingsStore.clearAll,
    ),
    DataStoreInfo(
      id: 'stt',
      sourceFile: 'lib/services/stt.dart',
      whatEn: 'Speech-to-text settings and the STT API key (Keychain)',
      whatHe: 'הגדרות תמלול ומפתח ה-STT (בצרור המפתחות)',
      where: 'SharedPreferences + secure storage',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: SttSettings.clearAll,
    ),
    DataStoreInfo(
      id: 'language',
      sourceFile: 'lib/services/strings.dart',
      whatEn: 'UI and speech language preferences',
      whatHe: 'העדפות שפת ממשק ודיבור',
      where: 'SharedPreferences',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: Strings.clear,
    ),
    DataStoreInfo(
      id: 'onboarding',
      sourceFile: 'lib/ui/onboarding_screen.dart',
      whatEn: 'Onboarding completed flag',
      whatHe: 'דגל סיום הדרכה ראשונית',
      where: 'SharedPreferences',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('onboarding.done');
        for (final key in prefs.getKeys()) {
          if (key.startsWith('onboarding.step.')) await prefs.remove(key);
        }
      },
    ),
    DataStoreInfo(
      id: 'tutorial',
      sourceFile: 'lib/services/tutorial.dart',
      whatEn: 'First-steps tutorial completion flag',
      whatHe: 'דגל סיום ההדרכה הראשונה',
      where: 'SharedPreferences',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('tutorial.done');
      },
    ),
    DataStoreInfo(
      id: 'permission_watchdog',
      sourceFile: 'lib/services/permission_watchdog.dart',
      whatEn: 'Baseline of granted permissions for revocation recovery',
      whatHe: 'רשימת ההרשאות שניתנו בעבר לזיהוי ביטול',
      where: 'SharedPreferences',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async {
        final prefs = await SharedPreferences.getInstance();
        for (final key in prefs.getKeys()) {
          if (key.startsWith('watchdog.granted.')) await prefs.remove(key);
        }
      },
    ),
    DataStoreInfo(
      id: 'privacy',
      sourceFile: 'lib/services/privacy_guard.dart',
      whatEn: 'Local-only mode toggle',
      whatHe: 'מתג מצב מקומי-בלבד',
      where: 'SharedPreferences',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('privacy.localOnly');
      },
    ),
    DataStoreInfo(
      id: 'watch_policy',
      sourceFile: 'lib/services/watch_policy.dart',
      whatEn: 'Screen-watching app allowlist and personal deny list',
      whatHe: 'רשימת האפליקציות המורשות לצפייה ורשימת חסימה אישית',
      where: 'SharedPreferences (watch.appAllowlist, watch.appUserDenylist)',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('watch.appAllowlist');
        await prefs.remove('watch.appUserDenylist');
      },
    ),
    DataStoreInfo(
      id: 'watch_suggestions',
      sourceFile: 'lib/services/watch_suggestions.dart',
      whatEn: 'Apps you muted screen-aware suggestions for (#214)',
      whatHe: 'אפליקציות שהשתקת עבורן הצעות (#214)',
      where: 'SharedPreferences (watch.suggestNeverApps)',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async => (await SharedPreferences.getInstance()).remove(
        'watch.suggestNeverApps',
      ),
    ),
    DataStoreInfo(
      id: 'wake_word',
      sourceFile: 'lib/services/wake_word.dart',
      whatEn: 'Wake word enabled toggle',
      whatHe: 'מתג מילת השכמה',
      where: 'SharedPreferences',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('wake_word.enabled');
      },
    ),
    DataStoreInfo(
      id: 'pairing',
      sourceFile: 'lib/link/phone_server.dart',
      whatEn: 'Pairing key hash (phone-Mac link trust)',
      whatHe: 'גיבוב מפתח ההתאמה (אמון קשר טלפון-מק)',
      where: 'SharedPreferences',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('link.keyHash');
      },
    ),
    DataStoreInfo(
      id: 'link_key',
      sourceFile: 'lib/link/mac_link.dart',
      whatEn: 'Link session key (phone-Mac pairing)',
      whatHe: 'מפתח סשן הקשר (התאמת טלפון-מק)',
      where: 'SharedPreferences',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('link.key');
      },
    ),
    DataStoreInfo(
      id: 'safety',
      sourceFile: 'lib/services/safety_gate.dart',
      whatEn: 'Safety gate toggle and app allowlist',
      whatHe: 'מתג שער הבטיחות ורשימת האפליקציות המורשות',
      where: 'SharedPreferences',
      retentionEn: 'Kept until you delete it',
      retentionHe: 'נשמר עד שמוחקים',
      clear: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('safety.enabled');
        await prefs.remove('safety.appAllowlist');
      },
    ),
  ];

  /// Wipes every registered store plus the remaining SharedPreferences keys
  /// and secure-storage items, returning the app to first-run state (#83).
  /// Deliberately does not touch the user's remote provider account data.
  static Future<void> deleteAll() async {
    final failures = <String>[];
    for (final store in stores) {
      try {
        await store.clear();
      } catch (e) {
        debugPrint('DataRegistry: clearing ${store.id} failed: $e');
        failures.add(store.id);
      }
    }
    if (failures.isNotEmpty) {
      throw StateError('Could not clear stores: ${failures.join(', ')}');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    try {
      await const FlutterSecureStorage().deleteAll();
    } on MissingPluginException {
      // Tests without a platform channel: prefs clear above already ran.
    }
  }
}
