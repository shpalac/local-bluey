import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/bluey_character.dart';
import 'package:local_bluey/ui/face_screen.dart';

/// Android-style viewport fixtures, not hardware validation.
void main() {
  const sizes = <Size>[
    Size(320, 568),
    Size(412, 915),
    Size(915, 412),
    Size(800, 1280),
  ];

  for (final size in sizes) {
    testWidgets('Android viewport face remains within bounds', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: FaceScreen(
              face: FaceState(
                gazeX: 0.6,
                gazeY: -0.4,
                mood: Mood.talking,
                talk: 0.7,
              ),
              awake: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final rect = tester.getRect(find.byType(BlueyCharacter));
      expect(rect.width, greaterThan(0));
      expect(rect.width, closeTo(rect.height, 0.01));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Android: RTL, large text and reduced motion', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: FaceScreen(
                face: FaceState(mood: Mood.happy),
                awake: true,
                bubble: 'תשובה קצרה',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(BlueyCharacter), findsOneWidget);
    expect(find.byKey(const ValueKey('speech-bubble')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
