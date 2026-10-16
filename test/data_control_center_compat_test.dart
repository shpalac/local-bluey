import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/workflows/legacy_routine_adapter.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingStore extends DataStoreInfo {
  _RecordingStore(String id, this.calls)
    : super(
        id: id,
        sourceFile: 'lib/services/data_registry.dart',
        whatEn: 'probe',
        whatHe: 'probe',
        where: 'test',
        retentionEn: 'test',
        retentionHe: 'test',
        clear: () async => calls.add(id),
      );

  final List<String> calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'ac4 routines stay convertible across a successful delete sweep',
    () async {
      const original = Routine(
        name: 'Reminder',
        trigger: 'remind me',
        instructions: 'notify:Take a break',
      );
      final before = original.toJson();

      final existing = DataRegistry.stores.toList();
      final calls = <String>[];
      DataRegistry.stores
        ..clear()
        ..addAll([_RecordingStore('alpha', calls)]);
      addTearDown(() {
        DataRegistry.stores
          ..clear()
          ..addAll(existing);
      });

      await DataRegistry.deleteAll();
      // Routines were swept as a registered store and the adapter path
      // still round-trips to the same manual workflow after deletion.
      final workflow = LegacyRoutineAdapter.toWorkflow(original);
      expect(workflow.trigger, 'manual');
      expect(workflow.steps.single.type, 'notify');
      final restored = LegacyRoutineAdapter.toRoutine(
        WorkflowDefinition.decode(workflow.encode()),
      );
      expect(restored.toJson(), before);
      expect(original.toJson(), before);
      // Fail-closed conversion survives a completed sweep untouched.
      expect(
        () => LegacyRoutineAdapter.toWorkflow(
          const Routine(
            name: 'unsafe',
            trigger: 'go',
            instructions: 'run shell command',
          ),
        ),
        throwsA(isA<LegacyRoutineConversionException>()),
      );
    },
  );

  test('ac4 the sweep stays identical across supported flavors', () async {
    final source = File('lib/services/data_registry.dart').readAsStringSync();
    expect(source.contains('TargetPlatform'), isFalse);
    expect(source.contains('defaultTargetPlatform'), isFalse);

    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final existing = DataRegistry.stores.toList();
        final calls = <String>[];
        DataRegistry.stores
          ..clear()
          ..addAll([_RecordingStore('alpha', calls)]);
        addTearDown(() {
          DataRegistry.stores
            ..clear()
            ..addAll(existing);
        });
        await DataRegistry.deleteAll();
        expect(calls, ['alpha'], reason: '$platform');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), isEmpty, reason: '$platform');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });
}
