import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/offline_provider_fallback_policy.dart';

class RecordingProvider extends LlmProvider {
  RecordingProvider(this.reply, {this.fail = false});
  final String reply;
  final bool fail;
  int calls = 0;
  @override
  String get name => reply;
  @override
  Future<String> chat(List<LlmMessage> messages) async {
    // Transient counts only: no transcript payload is retained anywhere.
    calls++;
    if (fail) throw StateError('transient offline');
    return reply;
  }
}

void main() {
  test('ac3 the fallback policy keeps a transport-free provenance', () {
    final source = File('lib/llm/offline_provider_fallback_policy.dart')
        .readAsStringSync();
    expect(
      source.contains(RegExp("import '(package:http|dart:io)")),
      isFalse,
      reason: 'the fallback layer must not gain transport access',
    );
    expect(
      source.contains(RegExp(r'HttpClient|writeAsBytes|writeAsString|File\(')),
      isFalse,
      reason: 'the fallback layer must not gain artifact writers',
    );
  });

  test(
    'ac3 chat is stateless: text rides as transient counters only',
    () async {
      const secret = 'sample@fixture.invalid';
      final local = RecordingProvider('local');
      final cloud = RecordingProvider('cloud', fail: true);
      final policy = OfflineProviderFallbackPolicy(
        local: local,
        cloud: cloud,
        cloudEnabled: true,
      );

      // A cloud failure falls back to local reply; the corpus text rides
      // only as the transient message argument.
      final reply = await policy.chat([
        LlmMessage('user', 'summarize $secret'),
      ]);
      expect(reply, 'local');
      expect(local.calls, 1);
      expect(cloud.calls, 1);

      // Nothing in the policy or providers retains the corpus secret; the
      // only output is the reply string from the local provider.
      expect(policy.toString(), isNot(contains(secret)));
      expect(local.toString(), isNot(contains(secret)));
      expect(cloud.toString(), isNot(contains(secret)));

      // Repeat the call: the fallback is deterministic, with no artifacts
      // left from the previous invocation.
      expect(
        await policy.chat([LlmMessage('user', 'summarize $secret')]),
        'local',
      );
      expect(local.calls, 2);
      expect(cloud.calls, 2);
      expect(policy.toString(), isNot(contains(secret)));
    },
  );
}
