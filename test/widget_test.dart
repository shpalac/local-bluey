import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/face_screen.dart';

void main() {
  testWidgets('face screen renders and shows bubble', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FaceScreen(face: FaceState(), awake: true, bubble: 'Hi there'),
      ),
    );
    expect(find.text('Hi there'), findsOneWidget);
  });

  test('packet json round-trip', () {
    final packet = Packet(
      face: FaceState(gazeX: 0.5, gazeY: -0.25, mood: Mood.talking, talk: 0.8),
      hello: 'iPhone',
      command: 'wake',
      callID: 'c1',
      tool: 'point_at',
      text: '@500,300',
    );
    final decoded = Packet.fromJson(Map<String, dynamic>.from(packet.toJson()));
    expect(decoded.hello, 'iPhone');
    expect(decoded.command, 'wake');
    expect(decoded.callID, 'c1');
    expect(decoded.tool, 'point_at');
    expect(decoded.text, '@500,300');
    expect(decoded.face!.gazeX, 0.5);
    expect(decoded.face!.gazeY, -0.25);
    expect(decoded.face!.mood, Mood.talking);
    expect(decoded.face!.talk, 0.8);
  });
}
