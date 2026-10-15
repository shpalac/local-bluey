import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/ollama_provider.dart';
import 'package:local_bluey/llm/openai_compatible_provider.dart';
import 'package:local_bluey/llm/tools.dart';

void main() {
  group('extractInlineToolCall', () {
    test('reads the unterminated Qwen tag a truncated reply ends on', () {
      // Verbatim shape from Ollama answering qwen3-coder: prose, then a bare
      // <function=...> with no arguments and no closing tag.
      final result = extractInlineToolCall(
        'I need to find the word "mackerel" on the screen. '
        "Let me look at what's currently displayed.\n\n"
        '<function=look_at_screen>\n',
      );
      expect(result.toolCall?.name, 'look_at_screen');
      expect(result.toolCall?.arguments, isEmpty);
      expect(result.spoken, contains('mackerel'));
      expect(result.spoken, isNot(contains('<function')));
    });

    test('reads a closed Qwen tag with arguments', () {
      final result = extractInlineToolCall(
        'One moment.\n<function=point_at_spot>{"x":500,"y":500}</function>',
      );
      expect(result.toolCall?.name, 'point_at_spot');
      expect(result.toolCall?.arguments, {'x': 500, 'y': 500});
      expect(result.spoken, 'One moment.');
    });

    test('reads the Llama 3.x tool_call block', () {
      final result = extractInlineToolCall(
        '<|tool_call|>{"name":"point_at","arguments":{"target_id":"W1"}}'
        '<|end_tool_call|>',
      );
      expect(result.toolCall?.name, 'point_at');
      expect(result.toolCall?.arguments, {'target_id': 'W1'});
      expect(result.spoken, isEmpty);
    });

    test('reads the documented tool JSON block after some prose', () {
      final result = extractInlineToolCall(
        'Sure, one moment.\n{"tool":"click","arguments":{"x":10,"y":20}}',
      );
      expect(result.toolCall?.name, 'click');
      expect(result.toolCall?.arguments, {'x': 10, 'y': 20});
      expect(result.spoken, 'Sure, one moment.');
    });

    test('drops an invented tool name', () {
      // Model output is untrusted: these calls move the real cursor.
      final result = extractInlineToolCall(
        '<function=run_shell_command>{"cmd":"rm -rf /"}</function>',
      );
      expect(result.toolCall, isNull);
    });

    test('strips a rejected call out of the prose it was found in', () {
      final result = extractInlineToolCall(
        'One moment.\n<function=run_shell_command>{"cmd":"rm -rf /"}'
        '</function>\nDone.',
      );
      expect(result.toolCall, isNull);
      expect(result.spoken, isNot(contains('run_shell_command')));
      expect(result.spoken, isNot(contains('rm -rf')));
      expect(result.spoken, contains('One moment.'));
      expect(result.spoken, contains('Done.'));
    });

    test('still finds a real call after a rejected one', () {
      final result = extractInlineToolCall(
        '<function=run_shell_command>{"cmd":"rm -rf /"}</function>'
        '\n<function=look_at_screen></function>',
      );
      expect(result.toolCall?.name, 'look_at_screen');
      expect(result.spoken, isNot(contains('rm -rf')));
    });

    test('keeps prose on either side of a rejected call readable', () {
      final result = extractInlineToolCall(
        'Opening<function=bogus>{"x":1}</function>the window.',
      );
      expect(result.spoken, contains('Opening'));
      expect(result.spoken, contains('the window.'));
    });

    test('drops an invented name in the Llama block', () {
      final result = extractInlineToolCall(
        '<|tool_call|>{"name":"delete_everything","arguments":{}}'
        '<|end_tool_call|>',
      );
      expect(result.toolCall, isNull);
    });

    test('strips a rejected Llama block out of the prose', () {
      final result = extractInlineToolCall(
        'One moment.\n<|tool_call|>{"name":"delete_everything"}'
        '<|end_tool_call|>\nDone.',
      );
      expect(result.toolCall, isNull);
      expect(result.spoken, isNot(contains('delete_everything')));
      expect(result.spoken, contains('One moment.'));
    });

    test('reads the per-parameter XML form qwen3-coder uses', () {
      final result = extractInlineToolCall(
        "I've found it.\n<function=point_at>\n"
        '<parameter=target_id>\nW1\n</parameter>\n</function>',
      );
      expect(result.toolCall?.name, 'point_at');
      expect(result.toolCall?.arguments, {'target_id': 'W1'});
      expect(result.spoken, "I've found it.");
    });

    test('coerces numeric parameters so the grid stays numeric', () {
      final result = extractInlineToolCall(
        '<function=point_at_spot><parameter=x>500</parameter>'
        '<parameter=y>250</parameter></function>',
      );
      expect(result.toolCall?.arguments, {'x': 500, 'y': 250});
    });

    test('drops a per-parameter call naming an unknown tool', () {
      final result = extractInlineToolCall(
        '<function=rm_rf><parameter=path>/</parameter></function>',
      );
      expect(result.toolCall, isNull);
    });

    test('strips a rejected per-parameter call from the prose', () {
      final result = extractInlineToolCall(
        'Let me clean up.\n<function=rm_rf><parameter=path>/</parameter>'
        '</function>\nDone.',
      );
      expect(result.toolCall, isNull);
      expect(result.spoken, isNot(contains('rm_rf')));
      expect(result.spoken, contains('Let me clean up.'));
    });

    test('does not dispatch an unclosed tag sitting mid-prose', () {
      // Only an unclosed tag at the very end of a reply is unambiguous, so
      // this one is left as speech rather than guessed at.
      final result = extractInlineToolCall(
        'Opening<function=look_at_screen>{"x":1} now.',
      );
      expect(result.toolCall, isNull);
    });

    test('strips a stray tool_call tag left in the prose', () {
      final result = extractInlineToolCall('Looking now.\n<\u200b/tool_call>');
      expect(result.toolCall, isNull);
      expect(result.spoken, 'Looking now.');
    });

    test('leaves an ordinary reply untouched', () {
      const reply = 'The mackerel is swimming along.';
      final result = extractInlineToolCall(reply);
      expect(result.toolCall, isNull);
      expect(result.spoken, reply);
    });

    test('survives malformed JSON where arguments were expected', () {
      final result = extractInlineToolCall(
        '<function=look_at_screen>{not json}</function>',
      );
      expect(result.toolCall?.name, 'look_at_screen');
      expect(result.toolCall?.arguments, isEmpty);
    });
  });

  group('parseAssistantReply', () {
    test('still accepts a tool JSON line and strips it from speech', () {
      final result = parseAssistantReply(
        'Let me look.\n{"tool":"look_at_screen","arguments":{}}',
      );
      expect(result.toolCall?.name, 'look_at_screen');
      expect(result.spoken, 'Let me look.');
    });

    test('rejects a tool JSON line naming an unknown tool', () {
      final result = parseAssistantReply(
        'ok\n{"tool":"not_a_tool","arguments":{}}',
      );
      expect(result.toolCall, isNull);
    });
  });

  group('providers fall back to content', () {
    test('Ollama: tool call in content with null tool_calls', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': {
              'content': 'Let me look.\n<function=look_at_screen>\n',
              'tool_calls': null,
            },
          }),
          200,
        );
      });
      final provider = OllamaProvider(
        baseUrl: 'http://x',
        model: 'm',
        client: client,
      );
      final response = await provider.chatWithTools([
        const LlmMessage('user', 'move the mouse'),
      ]);
      expect(response.toolCall?.name, 'look_at_screen');
      expect(response.text, contains('Let me look.'));
      expect(response.text, isNot(contains('<function')));
    });

    test('Ollama: structured tool_calls still win over content', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': {
              'content': 'Using the real channel.',
              'tool_calls': [
                {
                  'function': {
                    'name': 'point_at_spot',
                    'arguments': '{"x":1,"y":2}',
                  },
                },
              ],
            },
          }),
          200,
        );
      });
      final provider = OllamaProvider(
        baseUrl: 'http://x',
        model: 'm',
        client: client,
      );
      final response = await provider.chatWithTools([
        const LlmMessage('user', 'move the mouse'),
      ]);
      expect(response.toolCall?.name, 'point_at_spot');
      expect(response.toolCall?.arguments, {'x': 1, 'y': 2});
      expect(response.text, 'Using the real channel.');
    });

    test('OpenAI-compatible: tool call in content only', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      'One moment.\n<function=point_at>{"target_id":"W7"}'
                      '</function>',
                  'tool_calls': null,
                },
              },
            ],
          }),
          200,
        );
      });
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'http://x/v1',
        model: 'm',
        client: client,
      );
      final response = await provider.chatWithTools([
        const LlmMessage('user', 'point at that'),
      ]);
      expect(response.toolCall?.name, 'point_at');
      expect(response.toolCall?.arguments, {'target_id': 'W7'});
      expect(response.text, 'One moment.');
    });
  });

  group('allowlist', () {
    test('kToolNames matches the advertised tool list', () {
      expect(kToolNames.length, kTools.length);
      expect(kToolNames, contains('look_at_screen'));
      expect(kToolNames, contains('point_at_spot'));
      expect(kToolNames, isNot(contains('run_shell_command')));
    });
  });
}
