import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/watch_pipeline.dart';
import 'package:local_bluey/services/watch_suggestions.dart';
import 'package:shared_preferences/shared_preferences.dart';

WatchEvent _vision(String app) => WatchEvent(
  kind: WatchEventKind.visionCall,
  at: DateTime(2026, 10, 15),
  app: app,
  detail: 'same repeated failure',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'AC-1 persisted never-app preference suppresses repeated suggestions after restart',
    () async {
      await WatchSuggestions.neverForApp(' Terminal.app ');
      final first = WatchSuggestions();
      for (var i = 0; i < 4; i++) {
        expect(await first.onEvent(_vision('Terminal')), isNull);
      }
      await first.dispose();

      final restarted = WatchSuggestions();
      for (var i = 0; i < 4; i++) {
        expect(await restarted.onEvent(_vision('TERMINAL.app')), isNull);
      }
      expect(await WatchSuggestions.neverApps(), contains('terminal'));
      await restarted.dispose();
    },
  );

  test(
    'canonical never-app choices do not duplicate stored preferences',
    () async {
      await WatchSuggestions.neverForApp('Terminal.app');
      await WatchSuggestions.neverForApp(' TERMINAL ');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('watch.suggestNeverApps'), ['terminal']);
    },
  );

  test(
    'legacy app suffix suppression is honored without rewriting stored choices',
    () async {
      SharedPreferences.setMockInitialValues({
        'watch.suggestNeverApps': [' Terminal.app '],
      });
      final suggestions = WatchSuggestions();
      for (var i = 0; i < 4; i++) {
        expect(await suggestions.onEvent(_vision('Terminal')), isNull);
      }
      expect(await WatchSuggestions.neverApps(), contains('terminal'));
      await suggestions.dispose();
    },
  );
}
