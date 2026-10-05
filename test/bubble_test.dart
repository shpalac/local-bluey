import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/face_screen.dart';

void main() {
  testWidgets('streaming tokens keep ONE bubble widget (#130)', (tester) async {
    for (var i = 0; i < 200; i++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FaceScreen(face: FaceState(), bubble: 'token ' * i),
          ),
        ),
      );
    }
    // One keyed bubble, not 200 transitioning containers.
    expect(find.byKey(const ValueKey('speech-bubble')), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('long answers stay within the height cap and scroll (#130)', (
    tester,
  ) async {
    final long = 'word ' * 2000;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FaceScreen(face: FaceState(), bubble: long),
        ),
      ),
    );
    final bubble = tester.getRect(find.byKey(const ValueKey('speech-bubble')));
    final screen = tester.getRect(find.byType(Scaffold));
    expect(bubble.height, lessThanOrEqualTo(screen.height * 0.35 + 1));
  });

  testWidgets('no bubble, no widget', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FaceScreen(face: FaceState())),
      ),
    );
    expect(find.byKey(const ValueKey('speech-bubble')), findsNothing);
  });
}
