import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/egress_monitor.dart';
import 'package:local_bluey/services/settings_store.dart';

class FakeStorage implements EgressStorage {
  String? contents;
  bool failRead = false, failWrite = false, failDelete = false;
  Completer<void>? reading, writing;
  @override
  Future<String?> read() async {
    await reading?.future;
    if (failRead) throw StateError('read');
    return contents;
  }

  @override
  Future<void> write(String value) async {
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
  final now = DateTime.utc(2026, 10, 10);
  String row(String host, {DateTime? at}) => jsonEncode(
    EgressEntry(host: host, kind: 'brain', bytes: 10, at: at ?? now).toJson(),
  );
  EgressMonitor monitor(FakeStorage storage) =>
      EgressMonitor(storage: storage, now: () => now);

  test(
    'restart and first record preserve history; duplicate load is safe',
    () async {
      final storage = FakeStorage()..contents = row('old.example');
      final first = monitor(storage);
      await first.record('https://new.example/path?secret=hidden', 'tts', 20);
      await first.load();
      await first.load();
      expect(first.entries, hasLength(2));
      final restarted = monitor(storage);
      await restarted.load();
      expect(restarted.entries, hasLength(2));
      expect(restarted.report(), contains('old.example'));
      expect(storage.contents, isNot(contains('hidden')));
      expect(restarted.historyAvailable, isTrue);
    },
  );

  test(
    'missing history is known empty, uninitialized history is not',
    () async {
      final m = monitor(FakeStorage());
      expect(m.report(), contains('not fully available'));
      await m.load();
      expect(m.historyAvailable, isTrue);
      expect(m.report(), 'No transmissions in the retained record.');
    },
  );

  test(
    'corrupt/truncated rows do not erase valid metadata or imply zero',
    () async {
      final storage = FakeStorage()
        ..contents =
            '${row('valid.example')}\n{broken\n{"host":"bad","at":"bad"}\n';
      final m = monitor(storage);
      await m.load();
      expect(m.entries, hasLength(1));
      expect(m.historyAvailable, isFalse);
      expect(m.report(), contains('not fully available'));
      expect(m.report(), contains('valid.example'));
    },
  );

  test('age and count pruning restores the newest bounded metadata', () async {
    final storage = FakeStorage()
      ..contents = [
        row('expired', at: now.subtract(const Duration(days: 31))),
        for (var i = 0; i < 305; i++)
          row('host$i', at: now.subtract(Duration(minutes: 305 - i))),
      ].join('\n');
    final m = monitor(storage);
    await m.load();
    expect(m.entries, hasLength(300));
    expect(m.entries.first.host, 'host5');
    expect(m.entries.last.host, 'host304');
  });

  test(
    'delayed load settles before completed clear, without resurrection',
    () async {
      final storage = FakeStorage()
        ..contents = row('old.example')
        ..reading = Completer<void>();
      final m = monitor(storage);
      final loading = m.load();
      final clearing = m.clear();
      storage.reading!.complete();
      await Future.wait([loading, clearing]);
      await m.load();
      expect(m.entries, isEmpty);
      expect(storage.contents, isNull);
      expect(m.historyAvailable, isTrue);
    },
  );

  test(
    'delayed write settles before clear; fresh post-clear record survives',
    () async {
      final storage = FakeStorage()..writing = Completer<void>();
      final m = monitor(storage);
      final recording = m.record('https://old.example', 'brain', 10);
      final clearing = m.clear();
      storage.writing!.complete();
      await Future.wait([recording, clearing]);
      expect(storage.contents, isNull);
      expect(m.entries, isEmpty);
      await m.record('http://localhost', 'tts', 3);
      expect(m.entries.single.host, 'localhost');
      expect(storage.contents, isNot(contains('old.example')));
    },
  );

  test('read failure does not overwrite unknown disk history', () async {
    final storage = FakeStorage()
      ..contents = row('old.example')
      ..failRead = true;
    final m = monitor(storage);
    await m.record('https://new.example', 'brain', 2);
    expect(m.historyAvailable, isFalse);
    expect(storage.contents, isNot(contains('new.example')));
    storage.failRead = false;
    await m.load();
    expect(m.entries, hasLength(2));
    expect(m.historyAvailable, isTrue);
  });

  test('write failure is honest and queue remains usable', () async {
    final storage = FakeStorage()..failWrite = true;
    final m = monitor(storage);
    await m.record('http://localhost', 'brain', 3);
    expect(m.report(), contains('could not be saved'));
    storage.failWrite = false;
    await m.record('http://localhost', 'tts', 4);
    expect(m.historyAvailable, isTrue);
    expect(m.report(), contains('7 bytes'));
  });

  test(
    'failed deletion is reported; retry clear establishes empty history',
    () async {
      final storage = FakeStorage()
        ..contents = row('old.example')
        ..failDelete = true;
      final m = monitor(storage);
      await m.load();
      await expectLater(m.clear(), throwsStateError);
      expect(m.report(), contains('deletion failed'));
      storage.failDelete = false;
      await m.clear();
      expect(storage.contents, isNull);
      expect(m.historyAvailable, isTrue);
    },
  );

  test(
    'offline self-test loads prior remote history and reports unavailable',
    () async {
      const settings = BrainSettings(
        backend: BrainBackend.ollama,
        baseUrl: 'http://localhost:11434',
        model: 'qwen',
      );
      final storage = FakeStorage()..contents = row('remote.example');
      final m = monitor(storage);
      expect(
        (await m.offlineSelfTest(settings)).join(),
        contains('remote.example'),
      );
      final broken = monitor(FakeStorage()..failRead = true);
      expect(
        (await broken.offlineSelfTest(settings)).join(),
        contains('unavailable'),
      );
      expect(await monitor(FakeStorage()).offlineSelfTest(settings), isEmpty);
    },
  );
}
