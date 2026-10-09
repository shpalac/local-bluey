import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/tools.dart';
import 'package:local_bluey/services/action_log.dart';
import 'package:local_bluey/services/tool_executor.dart';

import 'tool_executor_test.dart' show FakeControl;

class MemoryActionStorage implements ActionStorage {
  String? contents;
  bool failRead = false, failWrite = false, failDelete = false;
  Completer<void>? reading, writing;
  final readEntered = Completer<void>();
  final writeEntered = Completer<void>();
  @override
  Future<String?> read() async {
    if (!readEntered.isCompleted) readEntered.complete();
    await reading?.future;
    if (failRead) throw StateError('read');
    return contents;
  }

  @override
  Future<void> write(String value) async {
    if (!writeEntered.isCompleted) writeEntered.complete();
    await writing?.future;
    if (failWrite) throw StateError('write');
    contents = value;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('delete');
    contents = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every executed tool is recorded under the run id', () async {
    final log = ActionLog(storage: MemoryActionStorage());
    final executor = ToolExecutor(control: FakeControl(), actionLog: log);
    executor.currentRunId = 'run-42';
    await executor.execute(ToolCall('look_at_screen', {}));
    await executor.execute(ToolCall('point_at', {'target_id': 'ok'}));
    expect(log.entries.where((e) => e.runId == 'run-42').length, 2);
    expect(log.summarizeRun('run-42'), contains('2 actions'));
  });

  test('failures carry recovery guidance in the summary', () async {
    final log = ActionLog(storage: MemoryActionStorage());
    final executor = ToolExecutor(control: FakeControl(), actionLog: log);
    executor.currentRunId = 'run-43';
    await executor.execute(ToolCall('click', {'x': 500, 'y': 500}));
    final summary = log.summarizeRun('run-43');
    expect(summary, contains('1 failed'));
    expect(summary, contains('re-look at the screen'));
  });

  test('unknown runs summarize cleanly', () async {
    final log = ActionLog(storage: MemoryActionStorage());
    await log.load();
    expect(log.summarizeRun('nope'), 'No actions in this run.');
  });

  final now = DateTime.utc(2026, 10, 10);
  ActionEntry entry(String id, {DateTime? at, Map<String, dynamic>? args}) =>
      ActionEntry(
        runId: id,
        tool: 'click',
        arguments: args ?? {},
        outcome: 'ok',
        at: at ?? now,
      );
  ActionLog logFor(MemoryActionStorage storage) =>
      ActionLog(storage: storage, now: () => now);
  String row(String id, {DateTime? at}) =>
      jsonEncode(entry(id, at: at).toJson());

  test(
    'temp-file restart and first record preserve order and grouping',
    () async {
      final dir = await Directory.systemTemp.createTemp('action-log-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/actions.jsonl');
      final storage = FileActionStorage(() async => file);
      final first = ActionLog(storage: storage, now: () => now);
      await first.record(entry('first'));
      final next = ActionLog(storage: storage, now: () => now);
      await next.record(entry('second'));
      await next.load();
      await next.load();
      expect(next.entries.map((e) => e.runId), ['first', 'second']);
      final restarted = ActionLog(storage: storage, now: () => now);
      await restarted.load();
      expect(restarted.entries.map((e) => e.runId), ['first', 'second']);
      expect(restarted.summarizeRun('first'), '1 actions, all succeeded.');
      await restarted.clear();
      expect(await file.exists(), isFalse);
      await restarted.load();
      expect(restarted.entries, isEmpty);
    },
  );

  test(
    'corrupt and malformed timestamps are skipped without overwrite',
    () async {
      final storage = MemoryActionStorage()
        ..contents = '${row('good')}\n{broken\n{}\n';
      final log = logFor(storage);
      final original = storage.contents;
      await log.load();
      expect(log.entries, hasLength(1));
      expect(log.historyAvailable, isFalse);
      expect(log.summarizeRun('missing'), contains('incomplete'));
      await log.record(entry('new'));
      expect(storage.contents, original);
      await log.clear();
      await log.record(entry('fresh'));
      expect(log.historyAvailable, isTrue);
      expect(storage.contents, isNot(contains('good')));
    },
  );

  test(
    'unreadable and failed writes report uncertainty without unknown overwrite',
    () async {
      final storage = MemoryActionStorage()
        ..contents = row('old')
        ..failRead = true;
      final log = logFor(storage);
      await log.record(entry('new'));
      expect(storage.contents, row('old'));
      expect(log.historyProblem, contains('read'));
      storage.failRead = false;
      await log.load();
      expect(log.entries.map((e) => e.runId), ['old', 'new']);
      storage.failWrite = true;
      await log.record(entry('unsaved'));
      expect(log.historyProblem, contains('saved'));
      storage.failWrite = false;
      await log.record(entry('retry'));
      expect(log.historyAvailable, isTrue);
      expect(storage.contents, contains('unsaved'));
    },
  );

  test('exact age cutoff and 600-row load/record cap keep 500', () async {
    final cutoff = now.subtract(const Duration(days: 30));
    final storage = MemoryActionStorage()
      ..contents = [
        row('expired', at: cutoff.subtract(const Duration(microseconds: 1))),
        row('edge', at: cutoff),
      ].join('\n');
    final log = logFor(storage);
    await log.load();
    expect(log.entries.single.runId, 'edge');
    for (var i = 0; i < 600; i++) {
      await log.record(entry('r$i'));
    }
    expect(log.entries, hasLength(500));
    expect(log.entries.first.runId, 'r100');
    final restored = logFor(storage);
    await restored.load();
    expect(restored.entries, hasLength(500));
    final many = MemoryActionStorage()
      ..contents = List.generate(600, (i) => row('l$i')).join('\n');
    final loaded = logFor(many);
    await loaded.load();
    expect(loaded.entries.first.runId, 'l100');
    expect(loaded.entries, hasLength(500));
  });

  test(
    'entered load completes before clear; later load cannot resurrect',
    () async {
      final storage = MemoryActionStorage()
        ..contents = row('old')
        ..reading = Completer<void>();
      final log = logFor(storage);
      final loading = log.load();
      await storage.readEntered.future;
      var cleared = false;
      final clearing = log.clear().then((_) {
        cleared = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cleared, isFalse);
      storage.reading!.complete();
      await Future.wait([loading, clearing]);
      await log.load();
      expect(log.entries, isEmpty);
      expect(storage.contents, isNull);
    },
  );

  test(
    'entered write and overlapping records precede clear; fresh work survives',
    () async {
      final storage = MemoryActionStorage()..writing = Completer<void>();
      final log = logFor(storage);
      final recording = log.record(entry('old'));
      await storage.writeEntered.future;
      final second = log.record(entry('second'));
      var cleared = false;
      final clearing = log.clear().then((_) {
        cleared = true;
      });
      final fresh = log.record(entry('fresh'));
      await Future<void>.delayed(Duration.zero);
      expect(cleared, isFalse);
      storage.writing!.complete();
      await Future.wait([recording, second, clearing, fresh]);
      expect(log.entries.single.runId, 'fresh');
      expect(storage.contents, isNot(contains('old')));
      expect(storage.contents, isNot(contains('second')));
    },
  );

  test(
    'delete failure propagates, preserves memory, queue can recover',
    () async {
      final storage = MemoryActionStorage();
      final log = logFor(storage);
      await log.record(entry('old'));
      storage.failDelete = true;
      await expectLater(log.clear(), throwsStateError);
      expect(log.entries.single.runId, 'old');
      expect(log.historyProblem, contains('deletion'));
      storage.failDelete = false;
      await log.clear();
      await log.record(entry('fresh'));
      expect(log.historyAvailable, isTrue);
    },
  );

  test('caller mutations cannot change retained arguments; UTF8 and structure bounded', () async {
    final nested = <String, dynamic>{
      'list': ['original'],
    };
    final args = <String, dynamic>{
      'nested': nested,
      'big': '😀' * 10000,
      'object': Object(),
    };
    final e = entry('snapshot', args: args);
    args.clear();
    (nested['list'] as List).add('mutated');
    final storage = MemoryActionStorage();
    final log = logFor(storage);
    await log.record(e);
    expect(storage.contents, contains('original'));
    expect(storage.contents, isNot(contains('mutated')));
    expect(utf8.encode(e.arguments['big']).length, lessThanOrEqualTo(1024));
    expect(e.arguments['object'], isNull);
    expect(() => e.arguments.clear(), throwsUnsupportedError);
    expect(
      () => (e.arguments['nested']['list'] as List).add('bad'),
      throwsUnsupportedError,
    );
    expect(() => log.entries.clear(), throwsUnsupportedError);
    final cycle = <String, dynamic>{};
    cycle['cycle'] = cycle;
    final bounded = entry('cycle', args: cycle);
    expect(jsonEncode(bounded.toJson()).length, lessThan(20000));
  });
}
