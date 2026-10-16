import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/bluey_character.dart';
import 'package:local_bluey/ui/joyful_bluey_painter.dart';

void main() {
  testWidgets('ac2 Rive fallback honors reduced motion when mounted alone', (
    tester,
  ) async {
    Future<void> render({required bool reducedMotion}) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: SizedBox(
            width: 160,
            height: 160,
            child: BlueyCharacter(
              face: FaceState(),
              awake: true,
              tint: Colors.blue,
              phase: 0.75,
              requestedRenderer: FaceRenderer.rive,
            ),
          ),
        ),
      ),
    );

    JoyfulBlueyPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<JoyfulBlueyPainter>()
        .single;

    await render(reducedMotion: true);
    expect(painter().phase, 0);

    await render(reducedMotion: false);
    expect(painter().phase, 0.75);
    expect(resolveFaceRenderer(FaceRenderer.rive), FaceRenderer.native);
    expect(tester.takeException(), isNull);
  });
}
