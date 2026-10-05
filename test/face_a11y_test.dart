import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/face_screen.dart';

void main() {
  testWidgets('face has a semantic wake action wired to the gesture handler', (
    tester,
  ) async {
    var wakeToggled = false;
    var holdStarted = false;
    var holdEnded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FaceScreen(
            face: FaceState(),
            onWakeChanged: (_) => wakeToggled = true,
            onHoldStart: () => holdStarted = true,
            onHoldEnd: () => holdEnded = true,
          ),
        ),
      ),
    );
    // The Semantics widget wrapping the face carries the actions (#131).
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byType(GestureDetector),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.onTap, isNotNull);
    expect(semantics.properties.customSemanticsActions, isNotNull);
    expect(
      semantics.properties.customSemanticsActions!.keys.map((a) => a.label),
      containsAll(<String>['Start listening', 'Stop and send']),
    );
    // Invoke the semantic action: same handler as the gesture.
    semantics.properties.onTap!.call();
    expect(wakeToggled, isTrue);
    for (final entry in semantics.properties.customSemanticsActions!.entries) {
      entry.value();
    }
    expect(holdStarted, isTrue);
    expect(holdEnded, isTrue);
  });

  testWidgets('status chip is a live region (#131)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FaceScreen(face: FaceState())),
      ),
    );
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.text('Listening'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.liveRegion, isTrue);
  });
}
