import 'package:flutter/foundation.dart';
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

  /// Isolated storage owner used by registry and Settings fixtures.
  static LanguagePreferences? debugOverride;
  static final _preferences = LanguagePreferences();

  /// Active shared owner for registry and Settings.
  static LanguagePreferences get preferences => debugOverride ?? _preferences;

  /// Last loaded or persisted UI choice.
  static UiLanguage get uiLanguage => preferences.uiLanguage;

  /// In-memory override retained for existing locale fixtures.
  static set uiLanguage(UiLanguage value) => preferences.uiLanguage = value;

  /// Last loaded or persisted speech choice.
  static String get speechLanguage => preferences.speechLanguage;

  /// In-memory override retained for existing transcription fixtures.
  static set speechLanguage(String value) => preferences.speechLanguage = value;

  /// Loads the persisted language choices in storage order.
  static Future<void> load() => preferences.load();

  /// Persists before publishing the UI choice.
  static Future<void> setUiLanguage(UiLanguage value) =>
      preferences.setUiLanguage(value);

  /// Persists before publishing the speech choice.
  static Future<void> setSpeechLanguage(String value) =>
      preferences.setSpeechLanguage(value);

  /// Explicitly removes both language preferences.
  static Future<void> clear() => preferences.clear();

  /// RTL when the UI language is explicitly Hebrew. 'system' follows the
  /// device locale (handled by MaterialApp localizations delegates).
  static bool get forceRtl => uiLanguage == UiLanguage.hebrew;

  /// Picks [en] or [he] for the active UI language ('system' resolves
  /// via the platform locale).
  static String t(String en, String he) =>
      uiLanguage == UiLanguage.hebrew ? he : en;
}

/// Generic storage error, without plugin details or an implied rollback.
class LanguageStorageException implements Exception {
  /// Creates a safe language storage failure.
  const LanguageStorageException();
  @override
  String toString() => 'Language preferences could not be updated.';
}

/// Shared ordered ownership of UI and speech preference storage.
class LanguagePreferences extends ChangeNotifier {
  /// Uses preferences by default, or injected actual storage operations.
  LanguagePreferences({
    Future<String?> Function(String)? read,
    Future<bool> Function(String, String)? write,
    Future<bool> Function(String)? remove,
  }) : _read =
           read ??
           ((key) async =>
               (await SharedPreferences.getInstance()).getString(key)),
       _write =
           write ??
           ((key, value) async =>
               (await SharedPreferences.getInstance()).setString(key, value)),
       _remove =
           remove ??
           ((key) async => (await SharedPreferences.getInstance()).remove(key));

  final Future<String?> Function(String) _read;
  final Future<bool> Function(String, String) _write;
  final Future<bool> Function(String) _remove;
  Future<void>? _tail;
  int _revision = 0;
  int _clearEpoch = 0;

  /// Last source-grounded UI choice, defaulting to System.
  UiLanguage uiLanguage = UiLanguage.system;

  /// Last source-grounded speech choice, defaulting to auto.
  String speechLanguage = 'auto';

  Future<void> _publishStored(int revision) async {
    final ui = await _read(Strings._kUiLanguage);
    final speech = await _read(Strings._kSpeechLanguage);
    if (revision != _revision) return;
    uiLanguage = UiLanguage.values.asNameMap()[ui] ?? UiLanguage.system;
    speechLanguage = speech ?? 'auto';
    notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final revision = ++_revision;
    final next = (_tail ?? Future<void>.value()).then((_) async {
      try {
        await action();
        await _publishStored(revision);
      } catch (_) {
        if (revision == _revision) {
          try {
            await _publishStored(revision);
          } catch (_) {}
        }
        throw const LanguageStorageException();
      }
    });
    final settled = next.catchError((_) {});
    _tail = settled;
    settled.then((_) {
      if (identical(_tail, settled)) _tail = null;
    });
    return next;
  }

  /// Loads both choices, rejecting superseded publication.
  Future<void> load() => _enqueue(() async {});

  Future<void> _set(String key, String value) {
    final epoch = _clearEpoch;
    return _enqueue(() async {
      if (epoch != _clearEpoch) return;
      if (!await _write(key, value)) throw const LanguageStorageException();
    });
  }

  /// Orders UI writes; clear invalidates earlier queued choices.
  Future<void> setUiLanguage(UiLanguage value) =>
      _set(Strings._kUiLanguage, value.name);

  /// Orders speech writes without discarding fresh UI choices.
  Future<void> setSpeechLanguage(String value) =>
      _set(Strings._kSpeechLanguage, value);

  /// Removes both keys in order, reconciling honest partial failures.
  Future<void> clear() {
    _clearEpoch++;
    return _enqueue(() async {
      if (!await _remove(Strings._kUiLanguage)) {
        throw const LanguageStorageException();
      }
      if (!await _remove(Strings._kSpeechLanguage)) {
        throw const LanguageStorageException();
      }
    });
  }
}
