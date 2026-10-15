import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/face_screen.dart';

/// CI captures Flutter-rendered layouts, NOT physical-device screenshots.
const captureEvidence = bool.fromEnvironment('CAPTURE_BLUEY');
const capturePlatform = String.fromEnvironment(
  'BLUEY_PLATFORM',
  defaultValue: 'linux',
);

void main() {
  const sizes = <String, Size>{
    'macos': Size(1280, 800),
    'linux': Size(1280, 800),
    'ios': Size(390, 844),
    'android': Size(412, 915),
  };

  testWidgets(
    'render joyful companion for $capturePlatform',
    (tester) async {
      final size = sizes[capturePlatform];
      expect(size, isNotNull);
      tester.view.physicalSize = size!;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: FaceScreen(
                face: FaceState(mood: Mood.happy),
                awake: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('mascot/evidence/$capturePlatform.png'),
      );
      expect(tester.takeException(), isNull);
    },
    skip: !captureEvidence,
  );
}
