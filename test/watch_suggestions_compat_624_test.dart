import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/services/watch_pipeline.dart';
import 'package:local_bluey/services/watch_suggestions.dart';
import 'package:shared_preferences/shared_preferences.dart';

WatchEvent _vision(String app, String detail) => WatchEvent(
  kind: WatchEventKind.visionCall,
  at: DateTime(2026, 10, 15, 12),
  app: app,
  detail: detail,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ac4 routines stay untouched across a suppression cycle', () async {
    const original = Routine(
      name: 'Reminder',
      trigger: 'remind me',
      instructions: 'notify:Take a break',
    );
    final before = original.toJson();

    await WatchSuggestions.neverForApp('Terminal.app');
    final suggestions = WatchSuggestions();
    expect(
      await suggestions.onEvent(_vision('Terminal', 'one problem')),
      isNull,
    );
    expect(
      await suggestions.onEvent(_vision('Terminal', 'one problem')),
      isNull,
    );
    expect(
      await suggestions.onEvent(_vision('Terminal', 'one problem')),
      isNull,
      reason: 'a never-app stays silent',
    );
    await suggestions.dispose();

    // The routine and its fields are byte-identical to before.
    expect(original.toJson(), before);
  });

  test(
    'ac4 suppression law is flavor-independent (no platform branch)',
    () async {
      final text = File('lib/services/watch_suggestions.dart')
          .readAsStringSync();
      // The layer owns one canonical normalization for every supported host:
      // no per-platform override exists in the suggestion layer.
      expect(text.contains('TargetPlatform'), isFalse);
      expect(text.contains('defaultTargetPlatform'), isFalse);

      // The same canonical choice is served on every flavor in practice.
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final suggestions = WatchSuggestions();
          expect(
            await suggestions.onEvent(_vision('Terminal', 'the problem')),
            isNull,
          );
          expect(
            await suggestions.onEvent(_vision('Terminal', 'the problem')),
            isNull,
          );
          expect(
            await suggestions.onEvent(_vision('Terminal', 'the problem')),
            isNotNull,
          );
          await suggestions.dispose();
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    },
  );
}
