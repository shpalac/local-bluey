import 'package:shared_preferences/shared_preferences.dart';

/// UI strings in the user's chosen UI language (#36). Speech language is a
/// separate setting used by transcription/TTS, so a Hebrew speaker can keep
/// an English UI or the other way around.
enum UiLanguage { system, english, hebrew }

/// Locale state and lookup for UI and speech languages (#36).
class Strings {
  Strings._();

  static const _kUiLanguage = 'ui.language';
  static const _kSpeechLanguage = 'speech.language';

  static UiLanguage uiLanguage = UiLanguage.system;
  static String speechLanguage = 'auto';

  /// Loads the persisted language choices.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    uiLanguage =
        UiLanguage.values.asNameMap()[prefs.getString(_kUiLanguage)] ??
        UiLanguage.system;
    speechLanguage = prefs.getString(_kSpeechLanguage) ?? 'auto';
  }

  /// Sets and persists the UI language.
  static Future<void> setUiLanguage(UiLanguage language) async {
    uiLanguage = language;
    await (await SharedPreferences.getInstance()).setString(
      _kUiLanguage,
      language.name,
    );
  }

  /// Sets and persists the speech (transcription/TTS) language.
  static Future<void> setSpeechLanguage(String language) async {
    speechLanguage = language;
    await (await SharedPreferences.getInstance()).setString(
      _kSpeechLanguage,
      language,
    );
  }

  /// Resets both language preferences (#83).
  static Future<void> clear() async {
    uiLanguage = UiLanguage.system;
    speechLanguage = 'auto';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUiLanguage);
    await prefs.remove(_kSpeechLanguage);
  }

  /// RTL when the UI language is explicitly Hebrew. 'system' follows the
  /// device locale (handled by MaterialApp localizations delegates).
  static bool get forceRtl => uiLanguage == UiLanguage.hebrew;

  /// Picks [en] or [he] for the active UI language ('system' resolves
  /// via the platform locale).
  static String t(String en, String he) =>
      uiLanguage == UiLanguage.hebrew ? he : en;
}
