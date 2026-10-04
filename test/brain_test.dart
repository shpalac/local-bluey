import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/brain.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/tools.dart';

void main() {
  test('system prompt lists all tools with required params', () {
    final prompt = buildSystemPrompt();
    for (final tool in kTools) {
      expect(prompt, contains(tool.name));
    }
    expect(prompt, contains('{"tool":'));
    expect(prompt, contains('target_id (required)'));
  });

  test('parses spoken text plus one tool call', () {
    final reply = parseAssistantReply(
      'Let me look at that for you.\n{"tool": "look_at_screen", "arguments": {}}\n',
    );
    expect(reply.spoken, 'Let me look at that for you.');
    expect(reply.toolCall!.name, 'look_at_screen');
    expect(reply.toolCall!.arguments, isEmpty);
  });

  test('parses tool call with arguments', () {
    final reply = parseAssistantReply(
      '{"tool": "click", "arguments": {"target_id": "C4", "double": true}}',
    );
    expect(reply.spoken, isEmpty);
    expect(reply.toolCall!.name, 'click');
    expect(reply.toolCall!.arguments['target_id'], 'C4');
    expect(reply.toolCall!.arguments['double'], true);
  });

  test('plain text stays spoken, invalid json ignored', () {
    final reply = parseAssistantReply('Sure thing! {not json}');
    expect(reply.spoken, 'Sure thing! {not json}');
    expect(reply.toolCall, isNull);
  });

  test('brain keeps history across ask and tool result', () async {
    final brain = Brain(provider: FakeProvider());
    final first = await brain.ask('what is on my screen?');
    expect(first.toolCall, isNotNull);
    final second = await brain.toolResult(
      'look_at_screen',
      'L1 @500,12 "Hello"',
    );
    expect(second.spoken, isNotEmpty);
    // system + user + assistant + tool + assistant
    expect(brain.history.length, 5);
    expect(brain.history.first.role, 'system');
    expect(brain.history.first.content, buildSystemPrompt());
  });

  _boundedHistoryTests();
}

class FakeProvider extends LlmProvider {
  int calls = 0;

  @override
  String get name => 'fake';

  @override
  Future<String> chat(List<LlmMessage> messages) async {
    calls++;
    if (calls == 1) {
      return 'One moment.\n{"tool": "look_at_screen", "arguments": {}}';
    }
    return 'I can see a window saying Hello.';
  }
}

class _EchoProvider extends LlmProvider {
  @override
  String get name => 'echo';
  @override
  Future<String> chat(List<LlmMessage> messages) async => 'ok';
}

void _boundedHistoryTests() {
  test('history is bounded and keeps the system prompt', () async {
    final brain = Brain(provider: _EchoProvider());
    for (var i = 0; i < 60; i++) {
      await brain.ask('message $i');
    }
    expect(brain.history.length, lessThanOrEqualTo(Brain.maxHistory));
    expect(brain.history.first.role, 'system');
  });

  test('older images are pruned, recent ones kept', () async {
    final brain = Brain(provider: _EchoProvider());
    await brain.ask('one', images: const ['img1']);
    await brain.ask('two', images: const ['img2']);
    await brain.ask('three', images: const ['img3']);
    final withImages = brain.history.where((m) => m.images.isNotEmpty);
    expect(withImages.length, lessThanOrEqualTo(Brain.keepImagesInLast + 1));
  });
}
