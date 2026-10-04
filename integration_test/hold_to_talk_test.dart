import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_bluey/llm/brain.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/services/tool_executor.dart';
import 'package:local_bluey/ui/face_screen.dart';

/// E2E: hold-to-talk gesture → (mock) transcription → mock LLM returns a
/// point_at tool call → the tool executor fires the warp through the Flutter
/// MethodChannel to the macOS native layer.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hold to talk triggers a native tool call', (tester) async {
    // Mock LLM: whatever the user asks, point at W12.
    final brain = Brain(provider: MockLlm());

    // Mock the native side of the MethodChannel and record what arrives.
    final nativeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('local_bluey/control'), (
          call,
        ) async {
          nativeCalls.add(call);
          switch (call.method) {
            case 'isTrusted':
              return true;
            case 'mouseLocation':
              return {'x': 42.0, 'y': 42.0};
            case 'resolveTarget':
              return {'x': 640.0, 'y': 360.0, 'text': 'OK'};
            default:
              return null;
          }
        });

    final executor = ToolExecutor(control: const ChannelControl());
    final bubble = ValueNotifier<String?>(null);
    var awake = true;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => FaceScreen(
            face: FaceState(mood: Mood.listening),
            awake: awake,
            bubble: bubble.value,
            onWakeChanged: (value) => setState(() => awake = value),
            onHoldStart: () async {
              // Stand-in for audio capture + transcription: the hold ends with
              // the user's words, here injected directly.
            },
            onHoldEnd: () async {
              final reply = await brain.ask('point at the OK button');
              bubble.value = reply.spoken;
              setState(() {});
              if (reply.toolCall != null) {
                await executor.execute(reply.toolCall!);
              }
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Simulate the hold-to-talk gesture: press, hold, release.
    final face = find.byType(FaceScreen);
    final center = tester.getCenter(face);
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    // The mock LLM's tool call must have reached the native layer.
    expect(
      brain.history.where((m) => m.role == 'user').single.content,
      'point at the OK button',
    );
    expect(bubble.value, 'There it is.');
    expect(nativeCalls.map((c) => c.method), contains('resolveTarget'));
    expect(nativeCalls.map((c) => c.method), contains('warp'));
    final warp = nativeCalls.firstWhere((c) => c.method == 'warp');
    expect(warp.arguments, {'x': 640.0, 'y': 360.0});
  });
}

class MockLlm extends LlmProvider {
  @override
  String get name => 'mock';

  @override
  Future<String> chat(List<LlmMessage> messages) async {
    return 'There it is.\n{"tool": "point_at", "arguments": {"target_id": "W12"}}';
  }
}
