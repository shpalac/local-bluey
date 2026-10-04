import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/services/characters.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reactions cycle and stay in character', () {
    expect(BlueyCharacters.bluey.react('wake', 0), 'Morning!');
    expect(BlueyCharacters.captain.react('wake', 0), 'Aye.');
    expect(BlueyCharacters.bluey.react('unknown', 0), '');
  });

  test('every character colors every mood', () {
    for (final c in BlueyCharacters.all) {
      for (final mood in Mood.values) {
        expect(c.moodColors[mood], isA<Color>(), reason: '${c.id} $mood');
      }
    }
  });

  test('selection persists and survives reload', () async {
    SharedPreferences.setMockInitialValues({});
    await CharacterStore.instance.select('captain');
    expect(CharacterStore.instance.current.value.name, 'Captain');
    await CharacterStore.instance.load();
    expect(CharacterStore.instance.current.value.id, 'captain');
  });

  test('unknown character id falls back to Bluey', () {
    expect(BlueyCharacters.byId('nobody').id, 'bluey');
  });
}
