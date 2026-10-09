import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/action_log.dart';
import 'package:local_bluey/services/conversation.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:local_bluey/services/egress_monitor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;
  setUp(() async {
    documents = await Directory.systemTemp.createTemp('egress-delete-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => documents.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await documents.delete(recursive: true);
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  group('store coverage (#83)', () {
    test('every persistence source file is registered', () {
      final markers = [
        'SharedPreferences.getInstance',
        'getApplicationDocumentsDirectory',
        'FlutterSecureStorage',
      ];
      final registered = DataRegistry.stores.map((s) => s.sourceFile).toSet()
        // The registry itself only clears stores on deleteAll; it owns no
        // persistent data of its own.
        ..add('lib/services/data_registry.dart');
      final offenders = <String>[];
      for (final dir in ['lib/services', 'lib/ui', 'lib/llm', 'lib/link']) {
        for (final file in Directory(dir).listSync(recursive: true)) {
          if (file is! File || !file.path.endsWith('.dart')) continue;
          final content = file.readAsStringSync();
          if (markers.any(content.contains) &&
              !registered.contains(file.path)) {
            offenders.add(file.path);
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'new persistent stores must register in DataRegistry',
      );
    });

    test(
      'action registry deletion orders older records and removes disk history',
      () async {
        final log = ActionLog.instance;
        await log.clear();
        final recording = log.record(
          ActionEntry(
            runId: 'registry-race',
            tool: 'click',
            arguments: {},
            outcome: 'ok',
          ),
        );
        final clearing = DataRegistry.stores
            .singleWhere((s) => s.id == 'action_log')
            .clear();
        await Future.wait([recording, clearing]);
        await log.load();
        expect(log.entries, isEmpty);
        expect(await File('${documents.path}/actions.jsonl').exists(), isFalse);
      },
    );

    test(
      'conversation registry deletion orders older adds and removes disk',
      () async {
        final store = ConversationStore.instance;
        await store.clear();
        final adding = store.add('user', 'older');
        final clearing = DataRegistry.stores
            .singleWhere((s) => s.id == 'conversation')
            .clear();
        await Future.wait([adding, clearing]);
        await store.load();
        expect(store.entries, isEmpty);
        expect(
          await File('${documents.path}/conversation.json').exists(),
          isFalse,
        );
      },
    );

    test('registered source files exist', () {
      for (final store in DataRegistry.stores) {
        expect(
          File(store.sourceFile).existsSync(),
          isTrue,
          reason: store.sourceFile,
        );
      }
    });
  });

  group('retention (#83)', () {
    test('action log prunes entries older than the retention window', () async {
      final log = ActionLog.instance;
      await log.clear();
      final old = ActionEntry(
        runId: 'r',
        tool: 'click',
        arguments: const {},
        outcome: 'ok',
        at: DateTime.now().subtract(
          Duration(days: ActionLog.retentionDays + 1),
        ),
      );
      await log.record(old);
      await log.record(
        ActionEntry(
          runId: 'r',
          tool: 'click',
          arguments: const {},
          outcome: 'ok',
        ),
      );
      expect(log.entries, hasLength(1));
      expect(log.entries.single.at, isNot(old.at));
    });

    test('egress monitor prunes old entries', () async {
      final monitor = EgressMonitor.instance;
      monitor.entries.clear();
      monitor.entries.add(
        EgressEntry(
          host: 'example.com',
          kind: 'llm',
          bytes: 1,
          at: DateTime.now().subtract(
            Duration(days: EgressMonitor.retentionDays + 1),
          ),
        ),
      );
      await monitor.record('https://example.com/v1', 'llm', 10);
      expect(monitor.entries, hasLength(1));
      expect(monitor.entries.single.bytes, 10);
    });
  });

  test(
    'delete-all reports store failures rather than clearing first-run flag',
    () async {
      SharedPreferences.setMockInitialValues({'onboarding.done': true});
      final stores = DataRegistry.stores.toList();
      DataRegistry.stores.clear();
      DataRegistry.stores.add(
        DataStoreInfo(
          id: 'failed',
          sourceFile: 'test',
          whatEn: 'test',
          whatHe: 'test',
          where: 'test',
          retentionEn: 'test',
          retentionHe: 'test',
          clear: () async => throw StateError('cannot delete'),
        ),
      );
      addTearDown(() {
        DataRegistry.stores.clear();
        DataRegistry.stores.addAll(stores);
      });
      await expectLater(DataRegistry.deleteAll(), throwsStateError);
      expect(
        (await SharedPreferences.getInstance()).getBool('onboarding.done'),
        isTrue,
      );
    },
  );

  group('delete all (#83)', () {
    test('deleteAll clears every registered store and preferences', () async {
      SharedPreferences.setMockInitialValues({
        'onboarding.done': true,
        'ui.language': 'hebrew',
      });
      final cleared = <String>[];
      final probe = DataStoreInfo(
        id: 'probe',
        sourceFile: 'lib/services/data_registry.dart',
        whatEn: 'probe',
        whatHe: 'probe',
        where: 'test',
        retentionEn: 'test',
        retentionHe: 'test',
        clear: () async => cleared.add('probe'),
      );
      DataRegistry.stores.add(probe);
      addTearDown(() => DataRegistry.stores.remove(probe));

      await DataRegistry.deleteAll();

      expect(cleared, ['probe']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding.done'), isNull);
      expect(prefs.getString('ui.language'), isNull);
      expect(ActionLog.instance.entries, isEmpty);
    });
  });
}
