import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/bluey_character.dart';

void main() {
  test('unavailable Rive renderer resolves to native fallback', () {
    expect(resolveFaceRenderer(FaceRenderer.rive), FaceRenderer.native);
    expect(resolveFaceRenderer(FaceRenderer.native), FaceRenderer.native);
  });

  testWidgets('Rive request still renders native face painter', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 200,
        height: 200,
        child: BlueyCharacter(
          face: FaceState(),
          awake: true,
          tint: Colors.blue,
          requestedRenderer: FaceRenderer.rive,
        ),
      ),
    ));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
