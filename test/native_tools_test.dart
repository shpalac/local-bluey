import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/openai_compatible_provider.dart';

void main() {
  test('parses tool_calls from an OpenAI-compatible reply', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      expect(body['tools'], isNotEmpty);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': 'Looking now.',
                'tool_calls': [
                  {
                    'function': {
                      'name': 'look_at_screen',
                      'arguments': '{}',
                    },
                  },
                ],
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
      const LlmMessage('user', 'what do you see'),
    ]);
    expect(response.text, 'Looking now.');
    expect(response.toolCall?.name, 'look_at_screen');
  });

  test('images ride as image_url parts', () async {
    final client = MockClient((request) async {
      expect(request.body, contains('image_url'));
      expect(request.body, contains('data:image/jpeg;base64,abc'));
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'ok'},
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
    await provider.chatWithTools([
      const LlmMessage('user', 'see', images: ['abc']),
    ]);
  });
}
