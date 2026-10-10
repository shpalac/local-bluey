import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../link/models.dart';

/// A selectable character: palette, voice, persona for the brain, and the
/// small reactions that make Bluey feel alive (#55).
class Character {
  const Character({
    required this.id,
    required this.name,
    required this.persona,
    required this.voice,
    required this.moodColors,
    required this.reactions,
  });

  /// Stable identifier, persisted as the user's choice.
  final String id;

  /// Display name.
  final String name;

  /// Injected into the brain's system prompt.
  final String persona;

  /// TTS voice id.
  final String voice;

  /// Face color per mood.
  final Map<Mood, Color> moodColors;

  /// Event -> line shown in the bubble ("wake", "success", "error").
  final Map<String, List<String>> reactions;

  /// Picks a reaction line for [event] deterministically by [seed];
  /// '' when the event has no lines.
  String react(String event, int seed) {
    final lines = reactions[event];
    if (lines == null || lines.isEmpty) return '';
    return lines[seed % lines.length];
  }
}

/// The built-in roster (#55).
class BlueyCharacters {
  /// The default character.
  static const bluey = Character(
    id: 'bluey',
    name: 'Bluey',
    persona: 'You are Bluey, a warm little helper. Short, friendly answers.',
    voice: 'alloy',
    moodColors: {
      Mood.listening: Color(0xFF5BC8E5),
      Mood.thinking: Color(0xFF9B8CE5),
      Mood.talking: Color(0xFF5BC8E5),
      Mood.happy: Color(0xFF6FE3A5),
      Mood.sleepy: Color(0xFF8A8F98),
      Mood.resting: Color(0xFF8A8F98),
      Mood.pointing: Color(0xFFF5C35B),
    },
    reactions: {
      'wake': ['Morning!', 'Hey hey.', 'Up and at it.'],
      'success': ['Done!', 'Nailed it.', 'There you go.'],
      'error': ['Hmm, that broke.', 'Ow. Try again?'],
    },
  );

  /// The alternate character.
  static const captain = Character(
    id: 'captain',
    name: 'Captain',
    persona: 'You are Captain, a brisk, dry-witted ship captain. Very short answers.',
    voice: 'onyx',
    moodColors: {
      Mood.listening: Color(0xFF3BAFDA),
      Mood.thinking: Color(0xFF7E6BC4),
      Mood.talking: Color(0xFF3BAFDA),
      Mood.happy: Color(0xFF4ECB71),
      Mood.sleepy: Color(0xFF6B7280),
      Mood.resting: Color(0xFF6B7280),
      Mood.pointing: Color(0xFFE8A33D),
    },
    reactions: {
      'wake': ['Aye.', 'On deck.', 'Report.'],
      'success': ['Shipshape.', 'Steady as she goes.'],
      'error': ['We hit a squall.', 'Man the pumps.'],
    },
  );

  /// Every selectable character.
  static const all = [bluey, captain];

  /// Looks up a character by [id]; unknown ids fall back to [bluey].
  static Character byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => bluey);
}

/// Safe character storage failure, without plugin details or rollback claims.
class CharacterStorageException implements Exception {
  /// Creates a generic preference failure.
  const CharacterStorageException();
  @override
  String toString() => 'Character preference could not be verified or updated.';
}

/// Orders actual selection storage and publishes only source-grounded choices.
class CharacterStore {
  /// Uses preferences by default, or injected actual operations for fixtures.
  CharacterStore({
    Future<String?> Function()? read,
    Future<bool> Function(String)? write,
    Future<bool> Function()? remove,
  }) : _read =
           read ??
           (() async =>
               (await SharedPreferences.getInstance()).getString(_kCharacter)),
       _write =
           write ??
           ((id) async => (await SharedPreferences.getInstance()).setString(
             _kCharacter,
             id,
           )),
       _remove =
           remove ??
           (() async =>
               (await SharedPreferences.getInstance()).remove(_kCharacter));

  static final _instance = CharacterStore();

  /// Isolated owner for registry fixtures; production uses the shared owner.
  @visibleForTesting
  static CharacterStore? debugOverride;

  /// The shared store used by consumers and the registry.
  static CharacterStore get instance => debugOverride ?? _instance;
  static const _kCharacter = 'character.id';
  final Future<String?> Function() _read;
  final Future<bool> Function(String) _write;
  final Future<bool> Function() _remove;
  Future<void>? _tail;
  int _revision = 0;
  int _clearEpoch = 0;
  bool _verified = false;

  /// Last verified character, initially the existing Bluey default.
  final ValueNotifier<Character> current = ValueNotifier(BlueyCharacters.bluey);

  /// Whether the retained choice has been verified by a successful current read.
  bool get verified => _verified;

  Future<void> _publishStored(int revision) async {
    final id = await _read();
    if (revision != _revision) return;
    _verified = true;
    current.value = BlueyCharacters.byId(id ?? BlueyCharacters.bluey.id);
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
          } catch (_) {
            // Keep the last verified character, never fabricate a new default.
            if (revision == _revision) _verified = false;
          }
        }
        throw const CharacterStorageException();
      }
    });
    final settled = next.catchError((_) {});
    _tail = settled;
    settled.then((_) {
      if (identical(_tail, settled)) _tail = null;
    });
    return next;
  }

  /// Loads the choice in storage order; failed reads retain prior state.
  Future<void> load() => _enqueue(() async {});

  /// Orders deletion after entered writes and invalidates older queued choices.
  Future<void> clear() {
    _clearEpoch++;
    return _enqueue(() async {
      if (!await _remove()) throw const CharacterStorageException();
    });
  }

  /// Persists the original ID then reconciles the actual stored choice.
  /// Unknown IDs continue to use the existing Bluey fallback without migration.
  Future<void> select(String id) {
    final epoch = _clearEpoch;
    return _enqueue(() async {
      if (epoch != _clearEpoch) return;
      if (!await _write(id)) throw const CharacterStorageException();
    });
  }
}
