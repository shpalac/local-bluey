import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/bluey_character.dart';
import 'package:local_bluey/ui/face_screen.dart';

void main() {
  testWidgets('new joyful mascot is the default on every screen size', (
    tester,
  ) async {
    final face = FaceState(mood: Mood.happy, gazeX: 0.7, talk: 0.8);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FaceScreen(face: face, awake: true)),
      ),
    );
    final mascot = tester.widget<BlueyCharacter>(find.byType(BlueyCharacter));
    expect(mascot.legacyArtwork, isFalse);
    expect(mascot.face.mood, Mood.happy);
    expect(mascot.face.gazeX, 0.7);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion freezes the mascot animation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: FaceScreen(
              face: FaceState(mood: Mood.talking, talk: 1),
              awake: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    final mascot = tester.widget<BlueyCharacter>(find.byType(BlueyCharacter));
    expect(mascot.phase, 0);
    expect(mascot.face.talk, 1);
    expect(tester.takeException(), isNull);
  });
}
