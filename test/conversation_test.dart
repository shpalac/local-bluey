import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/conversation.dart';

import 'support/conversation_storage.dart';

void main() {
  final now = DateTime.utc(2026, 10, 10);
  Map<String, dynamic> row(String text) =>
      ConversationEntry(role: 'user', text: text, at: now).toJson();
  ConversationStore store(MemoryConversationStorage storage) =>
      ConversationStore(storage: storage, now: () => now);

  test(
    'temp-file fresh-instance first add recovers, load is idempotent',
    () async {
      final dir = await Directory.systemTemp.createTemp('conversation-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/conversation.json');
      final storage = FileConversationStorage(() async => file);
      final first = ConversationStore(storage: storage, now: () => now);
      await first.add('user', 'first');
      final second = ConversationStore(storage: storage, now: () => now);
      await second.add('bluey', 'second');
      await second.load();
      await second.load();
      expect(second.entries.map((e) => e.text), ['first', 'second']);
      final restart = ConversationStore(storage: storage);
      await restart.load();
      expect(restart.entries.map((e) => e.role), ['user', 'bluey']);
      await restart.clear();
      await restart.load();
      expect(await file.exists(), isFalse);
      expect(restart.entries, isEmpty);
    },
  );
  test(
    'missing history known empty, blank turn unchanged, injected clock and cap',
    () async {
      final storage = MemoryConversationStorage();
      final log = store(storage);
      expect(log.historyAvailable, isFalse);
      await log.add('user', '  ');
      expect(storage.readEntered.isCompleted, isFalse);
      await log.load();
      expect(log.historyAvailable, isTrue);
      for (var i = 0; i < 205; i++) {
        await log.add('user', '$i');
      }
      expect(log.entries, hasLength(200));
      expect(log.entries.first.text, '5');
      expect(log.entries.last.at, now);
      expect(() => log.entries.clear(), throwsUnsupportedError);
      final restored = store(
        MemoryConversationStorage()
          ..contents = jsonEncode(List.generate(210, (i) => row('r$i'))),
      );
      await restored.load();
      expect(restored.entries, hasLength(200));
      expect(restored.entries.first.text, 'r10');
    },
  );
  test(
    'bad rows preserve valid entries and bytes, clear resets uncertainty',
    () async {
      final storage = MemoryConversationStorage()
        ..contents = jsonEncode([
          row('good'),
          {'role': 'user', 'text': 4, 'at': now.toIso8601String()},
          {'role': 'bluey', 'text': 'bad', 'at': 'bad'},
          {'role': 'wrong', 'text': 'bad', 'at': now.toIso8601String()},
          8,
        ]);
      final original = storage.contents;
      final log = store(storage);
      await log.load();
      expect(log.entries.single.text, 'good');
      expect(log.historyAvailable, isFalse);
      expect(log.historyProblem, contains('incomplete'));
      await log.add('bluey', 'new');
      expect(storage.contents, original);
      await log.clear();
      await log.add('user', 'fresh');
      expect(log.historyAvailable, isTrue);
      expect(log.entries.single.text, 'fresh');
    },
  );
  test(
    'malformed root and unreadable bytes are never overwritten on add',
    () async {
      for (final raw in ['{broken', '{}']) {
        final storage = MemoryConversationStorage()..contents = raw;
        final log = store(storage);
        await log.add('user', 'new');
        expect(storage.contents, raw);
        expect(log.historyAvailable, isFalse);
      }
      final storage = MemoryConversationStorage()
        ..contents = jsonEncode([row('old')])
        ..failRead = true;
      final log = store(storage);
      await log.add('user', 'new');
      expect(log.historyProblem, contains('read'));
      final original = storage.contents;
      expect(storage.contents, original);
      storage.failRead = false;
      await log.load();
      expect(log.entries.map((e) => e.text), ['old', 'new']);
    },
  );
  test(
    'entered read stays pending before clear then cannot resurrect',
    () async {
      final storage = MemoryConversationStorage()
        ..contents = jsonEncode([row('old')])
        ..reading = Completer<void>();
      final log = store(storage);
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
    'entered write, queued add, clear and fresh add settle in call order',
    () async {
      final storage = MemoryConversationStorage()..writing = Completer<void>();
      final log = store(storage);
      final adding = log.add('user', 'old');
      await storage.writeEntered.future;
      final second = log.add('bluey', 'second');
      var cleared = false;
      final clearing = log.clear().then((_) {
        cleared = true;
      });
      final fresh = log.add('user', 'fresh');
      await Future<void>.delayed(Duration.zero);
      expect(cleared, isFalse);
      storage.writing!.complete();
      await Future.wait([adding, second, clearing, fresh]);
      expect(log.entries.single.text, 'fresh');
      expect(storage.contents, isNot(contains('old')));
      expect(storage.contents, isNot(contains('second')));
    },
  );
  test(
    'write/delete failures report uncertainty; memory and queue recover',
    () async {
      final storage = MemoryConversationStorage()..failWrite = true;
      final log = store(storage);
      var notifications = 0;
      log.addListener(() => notifications++);
      await log.add('user', 'unsaved');
      expect(log.historyProblem, contains('saved'));
      expect(log.entries.single.text, 'unsaved');
      storage.failWrite = false;
      await log.add('bluey', 'retry');
      expect(log.historyAvailable, isTrue);
      storage.failDelete = true;
      await expectLater(log.clear(), throwsStateError);
      expect(log.entries, hasLength(2));
      expect(log.historyProblem, contains('deletion'));
      storage.failDelete = false;
      await log.clear();
      await log.add('user', 'fresh');
      expect(log.historyAvailable, isTrue);
      expect(log.entries.single.text, 'fresh');
      expect(notifications, greaterThanOrEqualTo(5));
    },
  );
}
