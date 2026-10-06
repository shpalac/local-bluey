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

/// Loads and persists the selected character (#55, cleared by #83).
class CharacterStore {
  CharacterStore._();

  /// The shared store.
  static final CharacterStore instance = CharacterStore._();

  static const _kCharacter = 'character.id';

  /// The active character; the UI listens to this.
  final ValueNotifier<Character> current = ValueNotifier(BlueyCharacters.bluey);

  /// Loads the stored choice (or the default) into [current].
  Future<void> load() async {
    final id =
        (await SharedPreferences.getInstance()).getString(_kCharacter) ??
        BlueyCharacters.bluey.id;
    current.value = BlueyCharacters.byId(id);
  }

  /// Resets to the default character and removes the stored choice (#83).
  Future<void> clear() async {
    current.value = BlueyCharacters.bluey;
    await (await SharedPreferences.getInstance()).remove(_kCharacter);
  }

  /// Selects and persists the character with [id].
  Future<void> select(String id) async {
    current.value = BlueyCharacters.byId(id);
    await (await SharedPreferences.getInstance()).setString(_kCharacter, id);
  }
}
