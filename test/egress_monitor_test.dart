import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/egress_monitor.dart';
import 'package:local_bluey/services/settings_store.dart';

void main() {
  test('report groups by host with kinds, bytes and last time', () async {
    final monitor = EgressMonitor.instance;
    monitor.entries.clear();
    await monitor.record('http://localhost:11434/api/chat', 'brain', 120);
    await monitor.record('https://api.openai.com/v1/chat', 'brain', 300);
    final report = monitor.report();
    expect(report, contains('localhost: 1 calls (brain), 120 bytes'));
    expect(report, contains('api.openai.com: 1 calls (brain), 300 bytes'));
  });

  test('empty report says nothing left', () {
    final monitor = EgressMonitor.instance..entries.clear();
    expect(monitor.report(), 'Nothing has left this Mac.');
  });

  test(
    'offline self-test flags remote endpoints and past remote egress',
    () async {
      final monitor = EgressMonitor.instance..entries.clear();
      await monitor.record('https://api.openai.com/v1/chat', 'brain', 10);
      final problems = await monitor.offlineSelfTest(
        const BrainSettings(
          backend: BrainBackend.openAiCompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o',
        ),
      );
      expect(problems, isNotEmpty);
      expect(problems.join(), contains('brain endpoint is remote'));
      expect(problems.join(), contains('api.openai.com'));
    },
  );

  test(
    'offline self-test passes with all-local config and clean log',
    () async {
      final monitor = EgressMonitor.instance..entries.clear();
      await monitor.record('http://localhost:11434/api/chat', 'brain', 10);
      final problems = await monitor.offlineSelfTest(
        const BrainSettings(
          backend: BrainBackend.ollama,
          baseUrl: 'http://localhost:11434',
          model: 'qwen',
        ),
      );
      expect(problems, isEmpty);
    },
  );
}
