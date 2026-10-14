import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/offline_provider_fallback_policy.dart';

class FakeProvider implements LlmProvider {
  FakeProvider(this.result, {this.fail = false});

  final String result;
  final bool fail;
  int calls = 0;

  @override
  String get name => result;

  @override
  Future<String> chat(List<LlmMessage> messages) async {
    calls++;
    if (fail) throw StateError('unavailable');
    return result;
  }
}

void main() {
  test('disabled cloud selects local provider and makes zero cloud requests', () async {
    final local = FakeProvider('local');
    final cloud = FakeProvider('cloud');
    final policy = OfflineProviderFallbackPolicy(
      local: local,
      cloud: cloud,
      cloudEnabled: false,
    );

    expect(await policy.chat(const [LlmMessage('user', 'hello')]), 'local');
    expect(cloud.calls, 0);
    expect(local.calls, 1);
  });

  test('cloud failure falls back locally without silent success failure', () async {
    final local = FakeProvider('local');
    final cloud = FakeProvider('cloud', fail: true);
    final policy = OfflineProviderFallbackPolicy(
      local: local,
      cloud: cloud,
      cloudEnabled: true,
    );

    expect(await policy.chat(const [LlmMessage('user', 'hello')]), 'local');
  });

  test('unusable providers expose explicit degraded failure', () async {
    final policy = OfflineProviderFallbackPolicy(
      local: FakeProvider('local', fail: true),
      cloud: FakeProvider('cloud', fail: true),
      cloudEnabled: true,
    );

    expect(
      () => policy.chat(const [LlmMessage('user', 'hello')]),
      throwsA(isA<OfflineProviderException>()),
    );
  });
}
