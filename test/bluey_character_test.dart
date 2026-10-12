import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/bluey_character.dart';
import 'package:local_bluey/ui/face_screen.dart';

void main() {
  Future<void> showFace(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    FaceState? face,
    bool awake = true,
    bool reducedMotion = false,
    ValueChanged<bool>? onWake,
    VoidCallback? onHoldStart,
    VoidCallback? onHoldEnd,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Scaffold(
            body: FaceScreen(
              face: face ?? FaceState(),
              awake: awake,
              onWakeChanged: onWake,
              onHoldStart: onHoldStart,
              onHoldEnd: onHoldEnd,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('character is responsive in portrait and landscape', (tester) async {
    for (final size in [const Size(390, 844), const Size(844, 390)]) {
      await showFace(tester, size: size);
      final character = tester.getRect(find.byKey(const ValueKey('bluey-character')));
      expect(character.width, greaterThan(0));
      expect(character.height, closeTo(character.width, 0.01));
      expect(character.left, greaterThanOrEqualTo(0));
      expect(character.top, greaterThanOrEqualTo(0));
      expect(character.right, lessThanOrEqualTo(size.width));
      expect(character.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('mood, gaze and speech follow incoming FaceState', (tester) async {
    final face = FaceState(
      gazeX: 0.8,
      gazeY: -0.7,
      mood: Mood.talking,
      talk: 0.9,
    );
    await showFace(tester, face: face);
    final character = tester.widget<BlueyCharacter>(find.byType(BlueyCharacter));
    expect(character.face.mood, Mood.talking);
    expect(character.face.gazeX, 0.8);
    expect(character.face.talk, 0.9);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion suppresses idle animation', (tester) async {
    await showFace(tester, reducedMotion: true);
    expect(tester.widget<BlueyCharacter>(find.byType(BlueyCharacter)).phase, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.widget<BlueyCharacter>(find.byType(BlueyCharacter)).phase, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wake and hold-to-talk gestures remain available', (tester) async {
    final wakes = <bool>[];
    var starts = 0;
    var ends = 0;
    await showFace(
      tester,
      awake: false,
      onWake: wakes.add,
      onHoldStart: () => starts++,
      onHoldEnd: () => ends++,
    );
    await tester.tap(find.byType(FaceScreen));
    await tester.pump(const Duration(milliseconds: 90));
    await tester.tap(find.byType(FaceScreen));
    await tester.pump(const Duration(milliseconds: 350));
    expect(wakes, [true]);

    await tester.longPress(find.byType(FaceScreen));
    expect(starts, 1);
    expect(ends, 1);
  });
}
