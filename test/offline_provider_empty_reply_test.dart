import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/offline_provider_fallback_policy.dart';

class ReplyProvider extends LlmProvider {
  ReplyProvider(this.reply);

  final String reply;
  int calls = 0;

  @override
  String get name => 'fixture';

  @override
  Future<String> chat(List<LlmMessage> messages) async {
    calls++;
    return reply;
  }
}

void main() {
  test('blank cloud reply falls back to local reply', () async {
    final cloud = ReplyProvider('  ');
    final local = ReplyProvider('local answer');
    final policy = OfflineProviderFallbackPolicy(
      local: local,
      cloud: cloud,
      cloudEnabled: true,
    );

    expect(await policy.chat(const [LlmMessage('user', 'hi')]), 'local answer');
    expect(cloud.calls, 1);
    expect(local.calls, 1);
  });

  test('blank local reply reports degraded failure', () async {
    final local = ReplyProvider('  ');
    final cloud = ReplyProvider('cloud answer');
    final policy = OfflineProviderFallbackPolicy(
      local: local,
      cloud: cloud,
      cloudEnabled: false,
    );

    await expectLater(
      policy.chat(const [LlmMessage('user', 'hi')]),
      throwsA(isA<OfflineProviderException>()),
    );
    expect(cloud.calls, 0);
    expect(local.calls, 1);
  });
}
